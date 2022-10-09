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
require 'set'
require 'json'

Channel = Concurrent::Channel
CacheSet = Set.new
CacheQue = {}
Output = {}

class DeadFinderRunner
  def run(target, options)
    begin
      page = Nokogiri::HTML(URI.open(target))

      nodeset_a = page.css('a')
      link_a = nodeset_a.map { |element| element['href'] }.compact
      nodeset_script = page.css('script')
      link_script = nodeset_script.map { |element| element['src'] }.compact
      nodeset_link = page.css('link')
      link_link = nodeset_link.map { |element| element['href'] }.compact

      link_merged = []
      link_merged.concat link_a, link_script, link_link

      Logger.target target
      Logger.sub_info "Found #{link_merged.length} point. [a:#{link_a.length}/s:#{link_script.length}/l:#{link_link.length}]"
      Logger.sub_info 'Checking'
      jobs    = Channel.new(buffer: :buffered, capacity: 1000)
      results = Channel.new(buffer: :buffered, capacity: 1000)

      (1..options['concurrency']).each do |w|
        Channel.go { worker(w, jobs, results, target, options) }
      end

      link_merged.uniq.each do |node|
        result = generate_url node, target
        jobs << result
      end
      jobs.close

      (1..link_merged.uniq.length).each do
        ~results
      end
      Logger.sub_done 'Done'
    rescue => e 
      Logger.error "[#{e}] #{target}"
    end
  end

  def worker(_id, jobs, results, target, options)
    jobs.each do |j|
      if !CacheSet.include? j
        CacheSet.add j
        begin
          CacheQue[j] = true
          URI.open(j, read_timeout: options['timeout'])
        rescue StandardError => e
          if e.to_s.include? '404 Not Found'
            Logger.found "[#{e}] #{j}"
            CacheQue[j] = false
            Output[target] = [] if Output[target].nil?
            Output[target].push j
          end
        end
      elsif !CacheQue[j]
        Logger.found "[404 Not Found] #{j}"
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
  gen_output
end

def run_file(filename, options)
  app = DeadFinderRunner.new
  File.open(filename).each do |line|
    target = line.gsub("\n", '')
    app.run target, options
  end
  gen_output
end

def run_url(url, options)
  app = DeadFinderRunner.new
  app.run url, options
  gen_output
end

def run_sitemap(sitemap_url, options)
  app = DeadFinderRunner.new
  base_uri = URI(sitemap_url)
  sitemap = SitemapParser.new sitemap_url, { recurse: true }
  sitemap.to_a.each do |url|
    turl = generate_url url, base_uri
    app.run turl, options
  end
  gen_output
end

def gen_output
  File.write options['output'], Output.to_json if options['output'] != ''
end

class DeadFinder < Thor
  class_option :concurrency, aliases: :c, default: 20, type: :numeric, desc: 'Set Concurrncy'
  class_option :timeout, aliases: :t, default: 10, type: :numeric, desc: 'Set HTTP Timeout'
  class_option :output, aliases: :o, default: '', type: :string, desc: 'Save JSON Result'

  desc 'pipe', 'Scan the URLs from STDIN. (e.g cat urls.txt | deadfinder pipe)'
  def pipe
    Logger.info 'Pipe mode'
    run_pipe options
  end

  desc 'file <FILE>', 'Scan the URLs from File. (e.g deadfinder file urls.txt)'
  def file(filename)
    Logger.info 'File mode'
    run_file filename, options
  end

  desc 'url <URL>', 'Scan the Single URL.'
  def url(url)
    Logger.info 'Single URL mode'
    run_url url, options
  end

  desc 'sitemap <SITEMAP-URL>', 'Scan the URLs from sitemap.'
  def sitemap(sitemap)
    Logger.info 'Sitemap mode'
    run_sitemap sitemap, options
  end

  desc 'version', 'Show version.'
  def version
    Logger.info "deadfinder #{VERSION}"
  end
end
