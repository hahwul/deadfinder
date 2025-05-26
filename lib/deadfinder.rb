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

  def self.run_pipe(options)
    DeadFinder::Logger.apply_options(options)
    DeadFinder::Logger.info 'Reading input from STDIN'
    app = Runner.new
    processed_urls = 0
    limit = options['limit'].to_i

    while (target = $stdin.gets&.chomp)
      if limit.positive? && processed_urls >= limit
        DeadFinder::Logger.info "Reached URL limit (#{limit}), stopping."
        break
      end
      run_with_target(target, options, app)
      processed_urls += 1
    end
    gen_output(options)
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
    DeadFinder::Logger.info "Found #{sitemap.to_a.size} URLs from #{sitemap_url}"
    processed_urls = 0
    limit = options['limit'].to_i

    sitemap.to_a.each do |url|
      if limit > 0 && processed_urls >= limit
        DeadFinder::Logger.info "Reached URL limit (#{limit}), stopping sitemap processing."
        break
      end
      turl = generate_url(url, base_uri)
      run_with_target(turl, options, app)
      processed_urls += 1
    end
    gen_output(options)
  end

  def self.run_with_input(options)
    DeadFinder::Logger.apply_options(options)
    DeadFinder::Logger.info "Reading input from file: #{filename}"
    app = Runner.new
    processed_urls = 0
    limit = options['limit'].to_i

    targets = yield # This will be the array of lines from File.foreach
    targets.each do |target|
      if limit.positive? && processed_urls >= limit
        DeadFinder::Logger.info "Reached URL limit (#{limit}), stopping."
        break
      end
      run_with_target(target, options, app)
      processed_urls += 1
    end
    gen_output(options)
  end

  def self.run_with_target(target, options, app = Runner.new)
    DeadFinder::Logger.target "Fetching #{target}"
    app.run(target, options)
  end

  def self.gen_output(options)
    return if options['output'].empty?

    output_data = DeadFinder.output.to_h
    format = options['output_format'].to_s.downcase

    content = case format
              when 'yaml', 'yml'
                output_data.to_yaml
              when 'csv'
                generate_csv(output_data)
              else
                JSON.pretty_generate(output_data)
              end

    File.write(options['output'], content)
  end

  def self.generate_csv(output_data)
    CSV.generate do |csv|
      csv << %w[target url]
      output_data.each do |target, urls|
        Array(urls).each { |url| csv << [target, url] }
      end
    end
  end
end
