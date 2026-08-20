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

    # Sentinel stored in the status cache when a URL could not be fetched
    # (connection refused, timeout, TLS failure, …). Real HTTP status codes are
    # always >= 0, so -1 unambiguously marks a connection error.
    ERROR_STATUS = -1

    private def build_headers(raw : Array(String), user_agent : String) : HTTP::Headers
      HttpClient.build_headers(raw, user_agent)
    end

    def run(target : String, options : Options,
            output : Hash(String, Array(String)),
            coverage_data : Hash(String, TargetCoverage),
            status_cache : Hash(String, Int32),
            mutex : Mutex)
      Deadfinder::Logger.apply_options(options)

      headers = build_headers(options.headers, options.user_agent)

      uri = URI.parse(target)
      # Follow redirects for the page itself: a target that moves (http -> https,
      # / -> /index.html, an apex -> www hop) would otherwise be parsed as an
      # empty redirect body and silently report zero links.
      response, final_uri = HttpClient.fetch(uri, options, headers, HttpClient::MAX_REDIRECTS)

      unless response.status.success?
        Deadfinder::Logger.error "Target page returned HTTP #{response.status_code} (links below, if any, come from that response): #{target}"
      end

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
      if link_info.empty?
        # Say so explicitly: silence here used to be indistinguishable from a
        # page that was fetched but never parsed.
        Deadfinder::Logger.sub_info "Discovered 0 URLs on this page, nothing to check."
      else
        Deadfinder::Logger.sub_info "Discovered #{total_links_count} URLs, currently checking them. [#{link_info}]"
      end

      # Relative links resolve against `<base href>` when the document declares
      # one, and otherwise against the URL the page was *finally* served from
      # (which differs from `target` whenever the request was redirected).
      base_url = document_base(page, final_uri.to_s)

      # Resolve all URLs and dedupe: distinct link nodes can resolve to the same
      # absolute URL, and each unique URL should be checked/recorded once per
      # target.
      resolved_urls = all_links.compact_map { |node| Deadfinder.generate_url(node, base_url) }.uniq

      # Channel-based concurrent workers. Guard against a non-positive
      # concurrency (e.g. `-c 0`): with zero workers nothing would drain `jobs`
      # and the main fiber would block forever on `results.receive`.
      worker_count = options.concurrency < 1 ? 1 : options.concurrency

      # Group by the URL that is actually requested. A fragment is a client-side
      # anchor and is never transmitted, so `/guide#install` and `/guide#usage`
      # are one request while both still appear in the report. Grouping (rather
      # than relying on the status cache) also keeps the guarantee that no two
      # workers ever fetch the same URL concurrently.
      grouped = {} of String => Array(String)
      resolved_urls.each do |url|
        (grouped[request_url(url)] ||= [] of String) << url
      end

      jobs = Channel(Tuple(String, Array(String))).new(1000)
      results = Channel(Nil).new(1000)

      worker_count.times do |w|
        spawn do
          worker(w, jobs, results, target, options, output, coverage_data, status_cache, mutex)
        end
      end

      jobs_size = grouped.size

      spawn do
        grouped.each { |request, originals| jobs.send({request, originals}) }
        jobs.close
      end

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

    def worker(id : Int32, jobs : Channel(Tuple(String, Array(String))), results : Channel(Nil),
               target : String, options : Options,
               output : Hash(String, Array(String)),
               coverage_data : Hash(String, TargetCoverage),
               status_cache : Hash(String, Int32),
               mutex : Mutex)
      loop do
        job = jobs.receive? || break
        request, linked_urls = job

        begin
          status_code = resolve_status(request, status_cache, mutex, options)
          # One request, but every link that pointed at it is recorded, so
          # fragment variants are neither lost nor re-fetched.
          linked_urls.each do |url|
            record_total(target, options, coverage_data, mutex)
            if status_code == ERROR_STATUS
              record_error(target, url, options, output, coverage_data, mutex)
            else
              record_status(target, url, status_code, options, output, coverage_data, mutex)
            end
          end
        rescue ex
          # A recording/logging failure (e.g. a broken STDOUT pipe under
          # `... | head`) must never kill the worker fiber or skip the result
          # send below — otherwise the main fiber blocks forever waiting for a
          # result that never arrives.
          Deadfinder::Logger.verbose "[record failed: #{ex}] #{request}" if options.verbose
        ensure
          # Always report job completion so jobs_size accounting stays balanced.
          results.send(nil)
        end
      end
    end

    # Returns the HTTP status for `url`, fetching it at most once across the
    # entire run. Subsequent references (including from other pages) reuse the
    # cached status, so every page that links to the URL is still attributed it
    # without paying for a second network request. `ERROR_STATUS` marks a
    # connection failure. Within a single target run resolved URLs are unique,
    # so no two workers ever fetch the same URL concurrently.
    private def resolve_status(url : String, status_cache : Hash(String, Int32),
                               mutex : Mutex, options : Options) : Int32
      if cached = mutex.synchronize { status_cache[url]? }
        return cached
      end

      status = begin
        check_url(url, options)
      rescue ex
        Deadfinder::Logger.verbose "[#{ex}] #{url}" if options.verbose
        ERROR_STATUS
      end

      mutex.synchronize { status_cache[url] = status }
      status
    end

    # Checks a single link. Redirects are deliberately *not* followed here: the
    # 30x status is itself the reported result (`--include30x`).
    private def check_url(url : String, options : Options) : Int32
      uri = URI.parse(url)
      headers = build_headers(options.worker_headers, options.user_agent)
      response, _ = HttpClient.fetch(uri, options, headers)
      response.status_code
    end

    # A fragment is a client-side anchor and never reaches the server, so it is
    # dropped from the URL that is actually requested.
    private def request_url(url : String) : String
      idx = url.index('#')
      return url if idx.nil? || idx == 0
      url[0, idx]
    end

    # Honors `<base href>` (the first one wins, per the HTML spec) so relative
    # links on pages that declare a document base resolve the way a browser
    # would instead of against the page URL.
    private def document_base(page : Lexbor::Parser, page_url : String) : String
      page.css("base").each do |element|
        href = element.attribute_by("href")
        next unless href
        href = href.strip
        next if href.empty?
        return Deadfinder.generate_url(href, page_url) || page_url
      end
      page_url
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

      # Skip the mutex entirely on the common "alive + no coverage" path
      # so we don't serialize every live link on the cache-set mutex.
      return unless dead || options.coverage

      mutex.synchronize do
        if dead
          output[target] ||= [] of String
          output[target] << url
        end
        if options.coverage
          coverage_data[target] ||= TargetCoverage.new
          coverage_data[target].dead += 1 if dead
          coverage_data[target].status_counts[status_code.to_s] =
            (coverage_data[target].status_counts[status_code.to_s]? || 0) + 1
        end
      end
    end

    private def record_error(target : String, url : String, options : Options,
                             output : Hash(String, Array(String)),
                             coverage_data : Hash(String, TargetCoverage),
                             mutex : Mutex) : Nil
      mutex.synchronize do
        output[target] ||= [] of String
        output[target] << url

        if options.coverage
          coverage_data[target] ||= TargetCoverage.new
          coverage_data[target].dead += 1
          coverage_data[target].status_counts["error"] =
            (coverage_data[target].status_counts["error"]? || 0) + 1
        end
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
