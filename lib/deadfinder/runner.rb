# frozen_string_literal: true

require 'concurrent-edge'
require 'nokogiri'
require 'open-uri'
require 'net/http'

begin
  require 'openssl'
rescue LoadError => e
  warn "Error loading OpenSSL: #{e.message}"
  warn ''
  warn 'This typically happens on macOS when Ruby was compiled against OpenSSL 1.1'
  warn 'but your system has been upgraded to OpenSSL 3.x.'
  warn ''
  warn 'To fix this issue, try one of the following:'
  warn '  1. Reinstall Ruby using the system OpenSSL:'
  warn '     - With rbenv: rbenv install <version> --force'
  warn '     - With rvm: rvm reinstall ruby-<version>'
  warn '  2. Use Homebrew to install deadfinder (recommended for macOS):'
  warn '     brew install deadfinder'
  warn '  3. Use the Docker image:'
  warn '     docker pull ghcr.io/hahwul/deadfinder:latest'
  warn ''
  raise
end

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
      DeadFinder::Logger.apply_options(options)
      headers = options['headers'].each_with_object({}) do |header, hash|
        kv = header.split(': ')
        hash[kv[0]] = kv[1]
      rescue StandardError
      end
      page = Nokogiri::HTML(URI.open(target, headers))
      links = extract_links(page)

      DeadFinder::Logger.debug "#{CACHE_QUE.size} URLs in queue, #{CACHE_SET.size} URLs in cache"

      if options['match'] != ''
        begin
          links.each do |type, urls|
        links[type] = urls.select { |url| DeadFinder::UrlPatternMatcher.match?(url, options['match']) }
          end
        rescue RegexpError => e
          DeadFinder::Logger.error "Invalid match pattern: #{e.message}"
        end
      end

      if options['ignore'] != ''
        begin
          links.each do |type, urls|
            links[type] = urls.reject { |url| DeadFinder::UrlPatternMatcher.ignore?(url, options['ignore']) }
          end
        rescue RegexpError => e
          DeadFinder::Logger.error "Invalid match pattern: #{e.message}"
        end
      end

      total_links_count = links.values.flatten.length
      link_info = links.map { |type, urls| "#{type}:#{urls.length}" if urls.length.positive? }
                       .compact.join(' / ')
      DeadFinder::Logger.sub_info "Discovered #{total_links_count} URLs, currently checking them. [#{link_info}]" unless link_info.empty?

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

      # Log coverage summary if tracking was enabled
      if options['coverage'] && DeadFinder.coverage_data[target] && DeadFinder.coverage_data[target][:total] > 0
        total = DeadFinder.coverage_data[target][:total]
        dead = DeadFinder.coverage_data[target][:dead]
        percentage = ((dead.to_f / total) * 100).round(2)
        DeadFinder::Logger.sub_info "Coverage: #{dead}/#{total} URLs are dead links (#{percentage}%)"
      end

      DeadFinder::Logger.sub_complete 'Task completed'
    rescue StandardError => e
      DeadFinder::Logger.error "[#{e}] #{target}"
    end

    def worker(_id, jobs, results, target, options)
      jobs.each do |j|
        if CACHE_SET[j]
          # Skip if already cached
        else
          CACHE_SET[j] = true
          # Track total URLs tested for coverage calculation (only if coverage flag is enabled)
          if options['coverage']
            DeadFinder.coverage_data[target] ||= { total: 0, dead: 0, status_counts: Hash.new(0) }
            DeadFinder.coverage_data[target][:total] += 1
          end

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
              DeadFinder::Logger.found "[#{status_code}] #{j}"
              CACHE_QUE[j] = false
              DeadFinder.output[target] ||= []
              DeadFinder.output[target] << j
              # Track dead URLs for coverage calculation (only if coverage flag is enabled)
              if options['coverage']
                DeadFinder.coverage_data[target][:dead] += 1
                DeadFinder.coverage_data[target][:status_counts][status_code] += 1
              end
            else
              DeadFinder::Logger.verbose_ok "[#{status_code}] #{j}" if options['verbose']
              # Track status for successful URLs
              DeadFinder.coverage_data[target][:status_counts][status_code] += 1 if options['coverage']
            end
          rescue StandardError => e
            DeadFinder::Logger.verbose "[#{e}] #{j}" if options['verbose']
            # Consider errored URLs as dead for coverage calculation (only if coverage flag is enabled)
            if options['coverage']
              DeadFinder.coverage_data[target][:dead] += 1
              DeadFinder.coverage_data[target][:status_counts]['error'] += 1
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
end
