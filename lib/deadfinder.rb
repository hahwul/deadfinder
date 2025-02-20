# frozen_string_literal: true

require 'English'
require 'thor'
require 'open-uri'
require 'nokogiri'
require 'deadfinder/utils'
require 'deadfinder/logger'
require 'deadfinder/version'
require 'deadfinder/runner'
require 'deadfinder/cli'
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
    run_with_input(options) { $stdin.gets&.chomp }
  end

  def self.run_file(filename, options)
    run_with_input(options) { File.foreach(filename).map(&:chomp) }
  end

  def self.run_url(url, options)
    run_with_target(url, options)
  end

  def self.run_sitemap(sitemap_url, options)
    Logger.set_silent if options['silent']
    Logger.info "Parsing sitemap: #{sitemap_url}"
    app = Runner.new
    base_uri = URI(sitemap_url)
    sitemap = SitemapParser.new(sitemap_url, recurse: true)
    sitemap.to_a.each do |url|
      turl = generate_url(url, base_uri)
      run_with_target(turl, options, app)
    end
    gen_output(options)
  end

  def self.run_with_input(options)
    Logger.set_silent if options['silent']
    Logger.info 'Reading input'
    app = Runner.new
    Array(yield).each do |target|
      run_with_target(target, options, app)
    end
    gen_output(options)
  end

  def self.run_with_target(target, options, app = Runner.new)
    Logger.target "Checking: #{target}"
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
