# frozen_string_literal: true

require 'English'
require 'thor'
require 'open-uri'
require 'nokogiri'
require 'deadfinder/utils'
require 'deadfinder/logger'
require 'concurrent-edge'
require 'sitemap-parser'

Channel = Concurrent::Channel

class DeadFinderRunner
  def run(target)
    page = Nokogiri::HTML(URI.open(target))
    nodeset = page.css('a')
    link_a = nodeset.map { |element| element['href'] }.compact
    Logger.target target
    jobs    = Channel.new(buffer: :buffered, capacity: 100)
    results = Channel.new(buffer: :buffered, capacity: 100)

    (1..20).each do |w|
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
  end

  def worker(id, jobs, results)
    jobs.each do |j|
      begin
        URI.open(j)
      rescue => exception
        if exception.to_s.include? '404 Not Found'
          Logger.found "[#{exception}] #{j}"
        end
      end  
      results << j
    end
  end
end

def run_pipe
  app = DeadFinderRunner.new
  while $stdin.gets
    target = $LAST_READ_LINE.gsub("\n", '')
    app.run target
  end
end

def run_file(filename)
  app = DeadFinderRunner.new
  File.open(filename).each do |line|
    target = line.gsub("\n", '')
    app.run target
  end
end

def run_url(url)
  app = DeadFinderRunner.new
  app.run url
end

def run_sitemap(sitemap_url)
  app = DeadFinderRunner.new
  sitemap = SitemapParser.new sitemap_url, {recurse: true}
  sitemap.to_a.each do |url|
    app.run url
  end
end

class DeadFinder < Thor
  
  desc 'pipe', 'Scan the URLs from STDIN. (e.g cat urls.txt | deadfinder pipe)'
  def pipe
    Logger.info 'Pipe mode'
    run_pipe
  end

  desc 'file', 'Scan the URLs from File. (e.g deadfinder file urls.txt)'
  def file(filename)
    Logger.info 'File mode'
    run_file filename
  end

  desc 'url', 'Scan the Single URL.'
  def url(url)
    Logger.info 'Single URL mode'
    run_url url
  end

  desc 'sitemap', 'Scan the URLs from sitemap.'
  def sitemap(sitemap)
    Logger.info 'Sitemap mode'
    run_sitemap sitemap
  end
end
