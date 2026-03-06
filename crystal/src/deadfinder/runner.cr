require "http/client"
require "uri"
require "lexbor"

module Deadfinder
  class Runner
    LINK_SELECTORS = {
      "anchor" => {"a", "href"},
      "script" => {"script", "src"},
      "link"   => {"link", "href"},
      "iframe" => {"iframe", "src"},
      "form"   => {"form", "action"},
      "object" => {"object", "data"},
      "embed"  => {"embed", "src"},
    }

    private def request_path(uri : URI) : String
      path = uri.path.presence || "/"
      if q = uri.query.presence
        "#{path}?#{q}"
      else
        path
      end
    end

    def run(target : String, options : Options,
            output : Hash(String, Array(String)),
            coverage_data : Hash(String, TargetCoverage),
            cache_set : Hash(String, Bool),
            mutex : Mutex)
      Deadfinder::Logger.apply_options(options)

      headers = HTTP::Headers.new
      options.headers.each do |header|
        parts = header.split(": ", 2)
        headers[parts[0]] = parts[1] if parts.size == 2
      end
      headers["User-Agent"] = options.user_agent

      uri = URI.parse(target)
      client = HttpClient.create(uri, options)
      response = client.get(request_path(uri), headers: headers)
      client.close

      page = Lexbor::Parser.new(response.body)
      links = extract_links(page)

      if !options.match.empty?
        begin
          links.each do |type, urls|
            links[type] = urls.select { |url| UrlPatternMatcher.match?(url, options.match) }
          end
        rescue ex : ArgumentError
          Deadfinder::Logger.error "Invalid match pattern: #{ex.message}"
        end
      end

      if !options.ignore.empty?
        begin
          links.each do |type, urls|
            links[type] = urls.reject { |url| UrlPatternMatcher.ignore?(url, options.ignore) }
          end
        rescue ex : ArgumentError
          Deadfinder::Logger.error "Invalid match pattern: #{ex.message}"
        end
      end

      all_links = links.values.flatten.uniq
      total_links_count = all_links.size
      link_info = links.compact_map { |type, urls|
        "#{type}:#{urls.size}" if urls.size > 0
      }.join(" / ")
      Deadfinder::Logger.sub_info "Discovered #{total_links_count} URLs, currently checking them. [#{link_info}]" unless link_info.empty?

      # Resolve all URLs
      resolved_urls = all_links.compact_map { |node| Deadfinder.generate_url(node, target) }

      # Channel-based concurrent workers
      jobs = Channel(String).new(1000)
      results = Channel(String).new(1000)

      options.concurrency.times do |w|
        spawn do
          worker(w, jobs, results, target, options, output, coverage_data, cache_set, mutex)
        end
      end

      resolved_urls.each { |url| jobs.send(url) }
      jobs_size = resolved_urls.size
      jobs.close

      jobs_size.times { results.receive }

      # Log coverage summary
      if options.coverage
        mutex.synchronize do
          if data = coverage_data[target]?
            if data.total > 0
              percentage = ((data.dead.to_f / data.total) * 100).round(2)
              Deadfinder::Logger.sub_info "Coverage: #{data.dead}/#{data.total} URLs are dead links (#{percentage}%)"
            end
          end
        end
      end

      Deadfinder::Logger.sub_complete "Task completed"
    rescue ex
      Deadfinder::Logger.error "[#{ex}] #{target}"
    end

    def worker(id : Int32, jobs : Channel(String), results : Channel(String),
               target : String, options : Options,
               output : Hash(String, Array(String)),
               coverage_data : Hash(String, TargetCoverage),
               cache_set : Hash(String, Bool),
               mutex : Mutex)
      loop do
        j = jobs.receive? || break

        already_cached = mutex.synchronize { cache_set[j]? }
        if already_cached
          results.send(j)
          next
        end

        mutex.synchronize { cache_set[j] = true }

        # Track total URLs tested for coverage
        if options.coverage
          mutex.synchronize do
            coverage_data[target] ||= TargetCoverage.new
            coverage_data[target].total += 1
          end
        end

        begin
          uri = URI.parse(j)
          client = HttpClient.create(uri, options)

          request_headers = HTTP::Headers.new
          request_headers["User-Agent"] = options.user_agent
          options.worker_headers.each do |header|
            parts = header.split(":", 2)
            if parts.size == 2
              request_headers[parts[0].strip] = parts[1].strip
            end
          end

          response = client.get(request_path(uri), headers: request_headers)
          client.close
          status_code = response.status_code

          if status_code >= 400 || (status_code >= 300 && options.include30x)
            Deadfinder::Logger.found "[#{status_code}] #{j}"
            mutex.synchronize do
              output[target] ||= [] of String
              output[target] << j
              if options.coverage
                coverage_data[target].dead += 1
                coverage_data[target].status_counts[status_code.to_s] =
                  (coverage_data[target].status_counts[status_code.to_s]? || 0) + 1
              end
            end
          else
            Deadfinder::Logger.verbose_ok "[#{status_code}] #{j}" if options.verbose
            if options.coverage
              mutex.synchronize do
                coverage_data[target].status_counts[status_code.to_s] =
                  (coverage_data[target].status_counts[status_code.to_s]? || 0) + 1
              end
            end
          end
        rescue ex
          Deadfinder::Logger.verbose "[#{ex}] #{j}" if options.verbose
          if options.coverage
            mutex.synchronize do
              coverage_data[target] ||= TargetCoverage.new
              coverage_data[target].dead += 1
              coverage_data[target].status_counts["error"] =
                (coverage_data[target].status_counts["error"]? || 0) + 1
            end
          end
        end

        results.send(j)
      end
    end

    private def extract_links(page : Lexbor::Parser) : Hash(String, Array(String))
      links = {} of String => Array(String)
      LINK_SELECTORS.each do |type, selector_info|
        tag, attr = selector_info
        urls = [] of String
        page.css(tag).each do |element|
          if val = element.attribute_by(attr)
            urls << val unless val.empty?
          end
        end
        links[type] = urls
      end
      links
    end
  end
end
