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
CacheSet = Concurrent::Map.new
CacheQue = Concurrent::Map.new
Output = Concurrent::Map.new

class DeadFinderRunner
  def default_options
    {
      'concurrency' => 50,
      'timeout' => 10,
      'output' => '',
      'headers' => [],
      'silent' => true
    }
  end

  def run(target, options)
    Logger.set_silent if options['silent']
    headers = options['headers'].each_with_object({}) do |header, hash|
      kv = header.split(': ')
      hash[kv[0]] = kv[1]
    rescue StandardError
    end
    page = Nokogiri::HTML(URI.open(target, headers))
    links = extract_links(page)

    total_links_count = links.values.flatten.length
    # Generate link info string for non-empty link types
    link_info = links.map { |type, urls| "#{type}:#{urls.length}" if urls.length.positive? }.compact.join(' / ')

    # Log the information if there are any links
    Logger.sub_info "Found #{total_links_count} URLs. [#{link_info}]" unless link_info.empty?
    Logger.sub_info 'Checking'

    jobs = Channel.new(buffer: :buffered, capacity: 1000)
    results = Channel.new(buffer: :buffered, capacity: 1000)

    (1..options['concurrency']).each do |w|
      Channel.go { worker(w, jobs, results, target, options) }
    end

    links.values.flatten.uniq.each do |node|
      result = generate_url(node, target)
      jobs << result unless result.nil?
    end

    jobs_size = jobs.size
    jobs.close

    (1..jobs_size).each do
      ~results
    end
    Logger.sub_done 'Done'
  rescue StandardError => e
    Logger.error "[#{e}] #{target}"
  end

  def worker(_id, jobs, results, target, options)
    jobs.each do |j|
      if CacheSet[j]
        Logger.found "[404 Not Found] #{j}" unless CacheQue[j]
      else
        CacheSet[j] = true
        begin
          CacheQue[j] = true
          URI.open(j, read_timeout: options['timeout'])
        rescue StandardError => e
          if e.to_s.include? '404 Not Found'
            Logger.found "[#{e}] #{j}"
            CacheQue[j] = false
            Output[target] ||= []
            Output[target] << j
          end
        end
      end
      results << j
    end
  end

  private

  def extract_links(page)
    {
      anchor: page.css('a').map { |element| element['href'] }.compact,
      script: page.css('script').map { |element| element['src'] }.compact,
      link: page.css('link').map { |element| element['href'] }.compact,
      iframe: page.css('iframe').map { |element| element['src'] }.compact,
      form: page.css('form').map { |element| element['action'] }.compact,
      object: page.css('object').map { |element| element['data'] }.compact,
      embed: page.css('embed').map { |element| element['src'] }.compact
    }
  end
end

def run_pipe(options)
  Logger.set_silent if options['silent']

  Logger.info 'Reading from STDIN'
  app = DeadFinderRunner.new
  while $stdin.gets
    target = $LAST_READ_LINE.chomp
    Logger.target "Checking: #{target}"
    app.run target, options
  end
  gen_output(options)
end

def run_file(filename, options)
  Logger.set_silent if options['silent']

  Logger.info "Reading: #{filename}"
  app = DeadFinderRunner.new
  File.foreach(filename) do |line|
    target = line.chomp
    Logger.target "Checking: #{target}"
    app.run target, options
  end
  gen_output(options)
end

def run_url(url, options)
  Logger.set_silent if options['silent']

  Logger.target "Checking: #{url}"
  app = DeadFinderRunner.new
  app.run url, options
  gen_output(options)
end

def run_sitemap(sitemap_url, options)
  Logger.set_silent if options['silent']
  Logger.info "Parsing sitemap: #{sitemap_url}"
  app = DeadFinderRunner.new
  base_uri = URI(sitemap_url)
  sitemap = SitemapParser.new sitemap_url, { recurse: true }
  sitemap.to_a.each do |url|
    turl = generate_url url, base_uri
    Logger.target "Checking: #{turl}"
    app.run turl, options
  end
  gen_output(options)
end

def gen_output(options)
  File.write(options['output'], Output.to_json) unless options['output'].empty?
end

class DeadFinder < Thor
  class_option :concurrency, aliases: :c, default: 50, type: :numeric, desc: 'Number of concurrency'
  class_option :timeout, aliases: :t, default: 10, type: :numeric, desc: 'Timeout in seconds'
  class_option :output, aliases: :o, default: '', type: :string, desc: 'File to write JSON result'
  class_option :headers, aliases: :H, default: [], type: :array, desc: 'Custom HTTP headers to send with request'
  class_option :silent, aliases: :s, default: false, type: :boolean, desc: 'Silent mode'

  desc 'pipe', 'Scan the URLs from STDIN. (e.g cat urls.txt | deadfinder pipe)'
  def pipe
    run_pipe options
  end

  desc 'file <FILE>', 'Scan the URLs from File. (e.g deadfinder file urls.txt)'
  def file(filename)
    run_file filename, options
  end

  desc 'url <URL>', 'Scan the Single URL.'
  def url(url)
    run_url url, options
  end

  desc 'sitemap <SITEMAP-URL>', 'Scan the URLs from sitemap.'
  def sitemap(sitemap)
    run_sitemap sitemap, options
  end

  desc 'version', 'Show version.'
  def version
    Logger.info "deadfinder #{VERSION}"
  end
end
