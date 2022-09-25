# frozen_string_literal: true

require 'English'
require 'thor'
require 'open-uri'
require 'nokogiri'
require 'deadfinder/utils'
require 'deadfinder/logger'
require 'deadfinder/version'
require 'concurrent-edge'
require 'sitemap-parser'

Channel = Concurrent::Channel

class DeadFinderRunner
  def run(target, options)
    page = Nokogiri::HTML(URI.open(target))
    nodeset = page.css('a')
    link_a = nodeset.map { |element| element['href'] }.compact
    Logger.target target
    Logger.sub_info "Found #{link_a.length} point"
    Logger.sub_info 'Checking'
    jobs    = Channel.new(buffer: :buffered, capacity: 100)
    results = Channel.new(buffer: :buffered, capacity: 100)

    (1..options['concurrency']).each do |w|
      Channel.go { worker(w, jobs, results) }
    end

    link_a.uniq.each do |node|
      result = generate_url node, target
      jobs << result
    end
    jobs.close

    (1..link_a.uniq.length).each do
      ~results
    end
    Logger.sub_info 'Done'
  end

  def worker(_id, jobs, results)
    jobs.each do |j|
      begin
        URI.open(j)
      rescue StandardError => e
        Logger.found "[#{e}] #{j}" if e.to_s.include? '404 Not Found'
      end
      results << j
    end
  end
end

def run_pipe(options)
  app = DeadFinderRunner.new
  while $stdin.gets
    target = $LAST_READ_LINE.gsub("\n", '')
    app.run target, options
  end
end

def run_file(filename, options)
  app = DeadFinderRunner.new
  File.open(filename).each do |line|
    target = line.gsub("\n", '')
    app.run target, options
  end
end

def run_url(url, options)
  app = DeadFinderRunner.new
  app.run url, options
end

def run_sitemap(sitemap_url, options)
  app = DeadFinderRunner.new
  sitemap = SitemapParser.new sitemap_url, { recurse: true }
  sitemap.to_a.each do |url|
    app.run url, options
  end
end

class DeadFinder < Thor
  class_option :concurrency, aliases: :c, default: 20, type: :numeric

  desc 'pipe', 'Scan the URLs from STDIN. (e.g cat urls.txt | deadfinder pipe)'
  def pipe
    Logger.info 'Pipe mode'
    run_pipe options
  end

  desc 'file', 'Scan the URLs from File. (e.g deadfinder file urls.txt)'
  def file(filename)
    Logger.info 'File mode'
    run_file filename, options
  end

  desc 'url', 'Scan the Single URL.'
  def url(url)
    Logger.info 'Single URL mode'
    run_url url, options
  end

  desc 'sitemap', 'Scan the URLs from sitemap.'
  def sitemap(sitemap)
    Logger.info 'Sitemap mode'
    run_sitemap sitemap, options
  end

  desc 'version', 'Show version.'
  def version
    Logger.info "deadfinder #{VERSION}"
  end
end
