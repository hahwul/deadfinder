# frozen_string_literal: true

require 'English'
require 'thor'
require 'open-uri'
require 'nokogiri'
require 'deadfinder/utils'
require 'deadfinder/logger'
require 'deadfinder/runner'
require 'deadfinder/cli'
require 'deadfinder/version'
require 'concurrent-edge'
require 'sitemap-parser'
require 'json'
require 'yaml'
require 'csv'

module DeadFinder
  Channel = Concurrent::Channel
  CACHE_SET = Concurrent::Map.new
  CACHE_QUE = Concurrent::Map.new

  @output = {}
  def self.output
    @output
  end

  def self.output=(val)
    @output = val
  end

  @coverage_data = {}
  def self.coverage_data
    @coverage_data
  end

  def self.coverage_data=(val)
    @coverage_data = val
  end

  def self.run_pipe(options)
    run_with_input(options) { $stdin.gets&.chomp }
  end

  def self.run_file(filename, options)
    run_with_input(options) { File.foreach(filename).map(&:chomp) }
  end

  def self.run_url(url, options)
    DeadFinder::Logger.apply_options(options)
    run_with_target(url, options)
    gen_output(options)
  end

  def self.run_sitemap(sitemap_url, options)
    DeadFinder::Logger.apply_options(options)
    app = Runner.new
    base_uri = URI(sitemap_url)
    sitemap = SitemapParser.new(sitemap_url, recurse: true)
    urls = sitemap.to_a
    urls = urls.first(options['limit']) if options['limit'].positive?
    DeadFinder::Logger.info "Found #{urls.size} URLs from #{sitemap_url}"
    urls.each do |url|
      turl = generate_url(url, base_uri)
      run_with_target(turl, options, app)
    end
    gen_output(options)
  end

  def self.run_with_input(options)
    DeadFinder::Logger.apply_options(options)
    DeadFinder::Logger.info 'Reading input'
    app = Runner.new
    targets = Array(yield)
    targets = targets.first(options['limit']) if options['limit'].positive?
    targets.each do |target|
      run_with_target(target, options, app)
    end
    gen_output(options)
  end

  def self.run_with_target(target, options, app = Runner.new)
    DeadFinder::Logger.target "Fetching #{target}"
    app.run(target, options)
  end

  def self.calculate_coverage
    coverage_summary = {}
    total_all_tested = 0
    total_all_dead = 0
    
    coverage_data.each do |target, data|
      total = data[:total]
      dead = data[:dead]
      coverage_percentage = total > 0 ? ((dead.to_f / total) * 100).round(2) : 0.0
      
      coverage_summary[target] = {
        total_tested: total,
        dead_links: dead,
        coverage_percentage: coverage_percentage
      }
      
      total_all_tested += total
      total_all_dead += dead
    end
    
    overall_coverage = total_all_tested > 0 ? ((total_all_dead.to_f / total_all_tested) * 100).round(2) : 0.0
    
    {
      targets: coverage_summary,
      summary: {
        total_tested: total_all_tested,
        total_dead: total_all_dead,
        overall_coverage_percentage: overall_coverage
      }
    }
  end

  def self.gen_output(options)
    return if options['output'].empty?

    output_data = DeadFinder.output.to_h
    format = options['output_format'].to_s.downcase

    # Include coverage data only if coverage tracking was used and data exists
    coverage_info = (coverage_data.any? && coverage_data.values.any? { |v| v[:total] > 0 }) ? calculate_coverage : nil

    content = case format
              when 'yaml', 'yml'
                output_with_coverage = coverage_info ? { 'dead_links' => output_data, 'coverage' => coverage_info } : output_data
                output_with_coverage.to_yaml
              when 'csv'
                generate_csv(output_data, coverage_info)
              else
                output_with_coverage = coverage_info ? { 'dead_links' => output_data, 'coverage' => coverage_info } : output_data
                JSON.pretty_generate(output_with_coverage)
              end

    File.write(options['output'], content)
  end

  def self.generate_csv(output_data, coverage_info = nil)
    CSV.generate do |csv|
      csv << %w[target url]
      output_data.each do |target, urls|
        Array(urls).each { |url| csv << [target, url] }
      end
      
      # Add coverage information as additional rows if available
      if coverage_info
        csv << [] # Empty row separator
        csv << ['Coverage Report']
        csv << %w[target total_tested dead_links coverage_percentage]
        coverage_info[:targets].each do |target, data|
          csv << [target, data[:total_tested], data[:dead_links], "#{data[:coverage_percentage]}%"]
        end
        csv << [] # Empty row separator
        csv << ['Overall Summary']
        csv << ['total_tested', 'total_dead', 'overall_coverage_percentage']
        summary = coverage_info[:summary]
        csv << [summary[:total_tested], summary[:total_dead], "#{summary[:overall_coverage_percentage]}%"]
      end
    end
  end
end
