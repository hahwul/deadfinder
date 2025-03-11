# frozen_string_literal: true

require 'concurrent-edge'
require 'nokogiri'
require 'open-uri'
require 'net/http'
require 'openssl'
require 'deadfinder/logger'
require 'deadfinder/http_client'
require 'deadfinder/url_pattern_matcher'

module DeadFinder
  # Runner class for executing the main logic
  class Runner
    def default_options
      {
        'concurrency' => 50,
        'timeout' => 10,
        'output' => '',
        'output_format' => 'json',
        'headers' => [],
        'worker_headers' => [],
        'silent' => true,
        'verbose' => false,
        'include30x' => false,
        'proxy' => '',
        'proxy_auth' => '',
        'match' => '',
        'ignore' => '',
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

      if options['match'] != ''
        begin
          links.each do |type, urls|
        links[type] = urls.select { |url| DeadFinder::UrlPatternMatcher.match?(url, options['match']) }
          end
        rescue RegexpError => e
          Logger.error "Invalid match pattern: #{e.message}"
        end
      end

      if options['ignore'] != ''
        begin
          links.each do |type, urls|
            links[type] = urls.reject { |url| DeadFinder::UrlPatternMatcher.ignore?(url, options['ignore']) }
          end
        rescue RegexpError => e
          Logger.error "Invalid match pattern: #{e.message}"
        end
      end

      total_links_count = links.values.flatten.length
      link_info = links.map { |type, urls| "#{type}:#{urls.length}" if urls.length.positive? }
                       .compact.join(' / ')
      Logger.sub_info "Found #{total_links_count} URLs, currently checking them. [#{link_info}]" unless link_info.empty?

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

      (1..jobs_size).each { ~results }
      Logger.sub_complete 'Task completed'
    rescue StandardError => e
      Logger.error "[#{e}] #{target}"
    end

    def worker(_id, jobs, results, target, options)
      jobs.each do |j|
        if !CACHE_SET[j]
          CACHE_SET[j] = true
          begin
            CACHE_QUE[j] = true
            uri = URI.parse(j)
            http = HttpClient.create(uri, options)

            request = Net::HTTP::Get.new(uri.request_uri)
            request['User-Agent'] = options['user_agent']
            options['worker_headers']&.each do |header|
              key, value = header.split(':', 2)
              request[key.strip] = value.strip
            end

            response = http.request(request)
            status_code = response.code.to_i

            if status_code >= 400 || (status_code >= 300 && options['include30x'])
              Logger.found "[#{status_code}] #{j}"
              CACHE_QUE[j] = false
              DeadFinder.output[target] ||= []
              DeadFinder.output[target] << j
            else
              Logger.verbose_ok "[#{status_code}] #{j}" if options['verbose']
            end
          rescue StandardError => e
            Logger.verbose "[#{e}] #{j}" if options['verbose']
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
end
