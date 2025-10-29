# frozen_string_literal: true

require 'English'
require 'thor'
require 'open-uri'
require 'nokogiri'
require 'deadfinder/utils'
require 'deadfinder/logger'
require 'deadfinder/runner'
require 'deadfinder/visualizer'
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
    urls = apply_limit(sitemap.to_a, options)
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
    targets = apply_limit(Array(yield), options)
    targets.each do |target|
      run_with_target(target, options, app)
    end
    gen_output(options)
  end

  def self.apply_limit(items, options)
    return items unless options['limit'].positive?

    items.first(options['limit'])
  end

  def self.run_with_target(target, options, app = Runner.new)
    DeadFinder::Logger.target "Fetching #{target}"
    app.run(target, options)
  end

  def self.calculate_coverage
    coverage_summary = {}
    total_all_tested = 0
    total_all_dead = 0
    overall_status_counts = Hash.new(0)

    coverage_data.each do |target, data|
      total = data[:total]
      dead = data[:dead]
      status_counts = data[:status_counts] || {}
      coverage_percentage = total.positive? ? ((dead.to_f / total) * 100).round(2) : 0.0

      coverage_summary[target] = {
        total_tested: total,
        dead_links: dead,
        coverage_percentage: coverage_percentage,
        status_counts: status_counts
      }

      total_all_tested += total
      total_all_dead += dead
      status_counts.each { |code, count| overall_status_counts[code] += count }
    end

    overall_coverage = total_all_tested.positive? ? ((total_all_dead.to_f / total_all_tested) * 100).round(2) : 0.0

    {
      targets: coverage_summary,
      summary: {
        total_tested: total_all_tested,
        total_dead: total_all_dead,
        overall_coverage_percentage: overall_coverage,
        overall_status_counts: overall_status_counts
      }
    }
  end

  def self.gen_output(options)
    output_data = DeadFinder.output.to_h
    coverage_info = calculate_coverage_if_enabled(options)

    write_output_file(output_data, coverage_info, options) unless options['output'].to_s.empty?
    generate_visualization(coverage_info, options) if should_visualize?(options, coverage_info)
  end

  def self.calculate_coverage_if_enabled(options)
    return nil unless options['coverage'] && coverage_data.any? && coverage_data.values.any? { |v| v[:total].positive? }

    calculate_coverage
  end

  def self.write_output_file(output_data, coverage_info, options)
    format = options['output_format'].to_s.downcase
    content = format_output(output_data, coverage_info, format)
    File.write(options['output'], content)
  end

  def self.format_output(output_data, coverage_info, format)
    output_with_coverage = build_output_with_coverage(output_data, coverage_info)

    case format
    when 'yaml', 'yml'
      output_with_coverage.to_yaml
    when 'csv'
      generate_csv(output_data, coverage_info)
    else
      JSON.pretty_generate(output_with_coverage)
    end
  end

  def self.build_output_with_coverage(output_data, coverage_info)
    coverage_info ? { 'dead_links' => output_data, 'coverage' => coverage_info } : output_data
  end

  def self.should_visualize?(options, coverage_info)
    options['visualize'] && !options['visualize'].empty? && coverage_info
  end

  def self.generate_visualization(coverage_info, options)
    DeadFinder::Visualizer.generate(coverage_info, options['visualize'])
  end

  def self.generate_csv(output_data, coverage_info = nil)
    CSV.generate do |csv|
      add_dead_links_to_csv(csv, output_data)
      add_coverage_to_csv(csv, coverage_info) if coverage_info
    end
  end

  def self.add_dead_links_to_csv(csv, output_data)
    csv << %w[target url]
    output_data.each do |target, urls|
      Array(urls).each { |url| csv << [target, url] }
    end
  end

  def self.add_coverage_to_csv(csv, coverage_info)
    csv << [] # Empty row separator
    csv << ['Coverage Report']
    csv << %w[target total_tested dead_links coverage_percentage]
    coverage_info[:targets].each do |target, data|
      csv << [target, data[:total_tested], data[:dead_links], "#{data[:coverage_percentage]}%"]
    end

    csv << [] # Empty row separator
    csv << ['Overall Summary']
    csv << %w[total_tested total_dead overall_coverage_percentage]
    summary = coverage_info[:summary]
    csv << [summary[:total_tested], summary[:total_dead], "#{summary[:overall_coverage_percentage]}%"]
  end
end
