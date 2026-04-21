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
      path = if HttpClient.proxy_configured?(options) && uri.scheme == "http"
               HttpClient.absolute_uri(uri)
             else
               request_path(uri)
             end
      response = client.get(path, headers: headers)
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
          Deadfinder::Logger.error "Invalid ignore pattern: #{ex.message}"
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
        url = jobs.receive? || break

        unless claim_url(url, cache_set, mutex)
          results.send(url)
          next
        end

        record_total(target, options, coverage_data, mutex)

        begin
          status_code = check_url(url, options)
          record_status(target, url, status_code, options, output, coverage_data, mutex)
        rescue ex
          Deadfinder::Logger.verbose "[#{ex}] #{url}" if options.verbose
          record_error(target, options, coverage_data, mutex)
        end

        results.send(url)
      end
    end

    # Returns true if this worker now owns `url` (first-time check),
    # false if another worker already claimed it.
    private def claim_url(url : String, cache_set : Hash(String, Bool), mutex : Mutex) : Bool
      mutex.synchronize do
        return false if cache_set[url]?
        cache_set[url] = true
        true
      end
    end

    private def check_url(url : String, options : Options) : Int32
      uri = URI.parse(url)
      client = HttpClient.create(uri, options)
      headers = HTTP::Headers.new
      headers["User-Agent"] = options.user_agent
      options.worker_headers.each do |header|
        parts = header.split(":", 2)
        if parts.size == 2
          headers[parts[0].strip] = parts[1].strip
        end
      end

      path = if HttpClient.proxy_configured?(options) && uri.scheme == "http"
               HttpClient.absolute_uri(uri)
             else
               request_path(uri)
             end
      response = client.get(path, headers: headers)
      client.close
      response.status_code
    end

    private def record_total(target : String, options : Options,
                             coverage_data : Hash(String, TargetCoverage),
                             mutex : Mutex) : Nil
      return unless options.coverage
      mutex.synchronize do
        coverage_data[target] ||= TargetCoverage.new
        coverage_data[target].total += 1
      end
    end

    private def record_status(target : String, url : String, status_code : Int32,
                              options : Options,
                              output : Hash(String, Array(String)),
                              coverage_data : Hash(String, TargetCoverage),
                              mutex : Mutex) : Nil
      dead = status_code >= 400 || (status_code >= 300 && options.include30x)
      if dead
        Deadfinder::Logger.found "[#{status_code}] #{url}"
      else
        Deadfinder::Logger.verbose_ok "[#{status_code}] #{url}" if options.verbose
      end

      mutex.synchronize do
        if dead
          output[target] ||= [] of String
          output[target] << url
        end
        if options.coverage
          coverage_data[target].dead += 1 if dead
          coverage_data[target].status_counts[status_code.to_s] =
            (coverage_data[target].status_counts[status_code.to_s]? || 0) + 1
        end
      end
    end

    private def record_error(target : String, options : Options,
                             coverage_data : Hash(String, TargetCoverage),
                             mutex : Mutex) : Nil
      return unless options.coverage
      mutex.synchronize do
        coverage_data[target] ||= TargetCoverage.new
        coverage_data[target].dead += 1
        coverage_data[target].status_counts["error"] =
          (coverage_data[target].status_counts["error"]? || 0) + 1
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
