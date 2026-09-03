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
      # Images and media. A broken <img> is one of the most common dead links
      # on a real site, yet none of these resources were visible at all before.
      # <source> covers all three of its parents (<picture>, <video>, <audio>).
      "image"        => {"img", "src"},
      "source"       => {"source", "src"},
      "video"        => {"video", "src"},
      "video-poster" => {"video", "poster"},
      "audio"        => {"audio", "src"},
      "track"        => {"track", "src"},
      "area"         => {"area", "href"},
    }

    # `srcset` holds a *list* of candidates with optional descriptors
    # (`img-480.png 480w, img-2x.png 2x`), so it is expanded by `parse_srcset`
    # rather than read verbatim like the single-URL attributes above.
    SRCSET_SELECTORS = {
      "image-srcset"  => {"img", "srcset"},
      "source-srcset" => {"source", "srcset"},
    }

    # Fragments that address the top of the document rather than an element.
    # `#` (empty) and `#top` are valid by definition (HTML spec, "scroll to the
    # fragment"), so `--check-anchors` must never report them as broken.
    TOP_FRAGMENT = "top"

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

      # Fragment targets are verified in a second, opt-in pass so the default
      # path never pays for reading a response body. It reuses `grouped`, so a
      # document that many fragments point at is still opened only once.
      verify_anchors(target, grouped, options, output, coverage_data, status_cache, mutex) if options.check_anchors

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
      SRCSET_SELECTORS.each do |type, selector_info|
        tag, attr = selector_info
        urls = [] of String
        page.css(tag).each do |element|
          if val = element.attribute_by(attr)
            urls.concat(parse_srcset(val))
          end
        end
        links[type] = urls
      end
      links
    end

    # Expands a `srcset` attribute into its candidate URLs, following the HTML
    # spec's "parse a srcset attribute" grammar rather than splitting on every
    # comma: a URL may legally *contain* commas (`/a,b.png 2x`), and the comma
    # that separates candidates is only recognised after the URL token ends.
    # A URL token runs to the next whitespace; if it ends with commas those are
    # the separator (`a.png, b.png`) and the candidate has no descriptor,
    # otherwise the descriptor runs to the next comma outside parentheses.
    private def parse_srcset(value : String) : Array(String)
      urls = [] of String
      # Scan over chars, not the String: `String#[](Int)` is O(n) for anything
      # that is not pure ASCII, which would make this quadratic on a srcset
      # holding a non-ASCII path.
      chars = value.chars
      pos = 0
      size = chars.size

      while pos < size
        # Separators between candidates: whitespace and commas alike.
        while pos < size && (chars[pos].ascii_whitespace? || chars[pos] == ',')
          pos += 1
        end
        break if pos >= size

        start = pos
        while pos < size && !chars[pos].ascii_whitespace?
          pos += 1
        end
        url = chars[start...pos].join

        if url.ends_with?(',')
          url = url.rstrip(',')
        else
          # Skip this candidate's descriptor. Parentheses are tracked because
          # the grammar allows a parenthesised descriptor whose contents may
          # contain commas that do not end the candidate.
          in_parens = false
          while pos < size
            char = chars[pos]
            break if char == ',' && !in_parens
            in_parens = true if char == '('
            in_parens = false if char == ')'
            pos += 1
          end
        end

        urls << url unless url.empty?
      end

      urls
    end

    # Verifies `#fragment` targets (`--check-anchors`). This needs the response
    # *body*, which the status-only link check deliberately never keeps, so it
    # runs as a separate opt-in pass.
    #
    # It reads `status_cache` rather than re-deciding anything: only a document
    # that answered 2xx is worth opening, and every other outcome was already
    # reported (or deliberately not) by the link pass above.
    private def verify_anchors(target : String, grouped : Hash(String, Array(String)),
                               options : Options,
                               output : Hash(String, Array(String)),
                               coverage_data : Hash(String, TargetCoverage),
                               status_cache : Hash(String, Int32),
                               mutex : Mutex) : Nil
      # request URL => the linked URLs that carry a verifiable fragment, paired
      # with the decoded fragment. Keyed by request URL so the "one fetch per
      # document" grouping established above is not regressed into one fetch
      # per fragment.
      pending = {} of String => Array(Tuple(String, String))

      mutex.synchronize do
        grouped.each do |request, linked_urls|
          status = status_cache[request]?
          next unless status && status >= 200 && status < 300
          linked_urls.each do |url|
            fragment = checkable_fragment(url)
            next unless fragment
            (pending[request] ||= [] of Tuple(String, String)) << {url, fragment}
          end
        end
      end

      return if pending.empty?

      worker_count = options.concurrency < 1 ? 1 : options.concurrency
      jobs = Channel(Tuple(String, Array(Tuple(String, String)))).new(1000)
      results = Channel(Nil).new(1000)

      worker_count.times do
        spawn do
          anchor_worker(jobs, results, target, options, output, coverage_data, mutex)
        end
      end

      jobs_size = pending.size

      # Feed from its own fiber: `pending` can exceed the channel buffer, and a
      # blocked main fiber would never reach `results.receive`.
      spawn do
        pending.each { |request, entries| jobs.send({request, entries}) }
        jobs.close
      end

      jobs_size.times { results.receive }
    end

    private def anchor_worker(jobs : Channel(Tuple(String, Array(Tuple(String, String)))),
                              results : Channel(Nil), target : String, options : Options,
                              output : Hash(String, Array(String)),
                              coverage_data : Hash(String, TargetCoverage),
                              mutex : Mutex)
      loop do
        job = jobs.receive? || break
        request, entries = job

        begin
          ids = anchor_ids(request, options)
          # nil means the document could not be re-read or is not HTML. A
          # fragment we cannot verify is left alone rather than guessed at.
          if ids
            entries.each do |entry|
              url, fragment = entry
              next if ids.includes?(fragment)
              # Deliberately not "[404]": a live page missing an anchor is a
              # different defect from a page that does not exist, and the log
              # line has to say which one the user is looking at.
              Deadfinder::Logger.found "[anchor-missing] #{url}"
              record_dead_anchor(target, url, options, output, coverage_data, mutex)
            end
          end
        rescue ex
          Deadfinder::Logger.verbose "[anchor check failed: #{ex}] #{request}" if options.verbose
        ensure
          # Mirror `worker`: always report completion so the accounting in
          # `verify_anchors` stays balanced even when logging blows up.
          results.send(nil)
        end
      end
    end

    # Every fragment name `url` offers, or nil when the response cannot answer
    # the question (not fetchable, not a success, or not HTML — a fragment on a
    # PDF or a plain-text file is not ours to judge).
    private def anchor_ids(url : String, options : Options) : Set(String)?
      uri = URI.parse(url)
      headers = build_headers(options.worker_headers, options.user_agent)
      response, _ = HttpClient.fetch(uri, options, headers)
      return nil unless response.status.success?

      content_type = response.headers["Content-Type"]?
      return nil unless content_type && content_type.downcase.includes?("html")

      page = Lexbor::Parser.new(response.body)
      ids = Set(String).new
      page.css("[id]").each do |element|
        if value = element.attribute_by("id")
          ids << value unless value.empty?
        end
      end
      # Pre-HTML5 documents still address sections via `<a name="install">`,
      # which browsers honor as a fragment target to this day.
      page.css("a[name]").each do |element|
        if value = element.attribute_by("name")
          ids << value unless value.empty?
        end
      end
      ids
    end

    # The fragment of `url` in the form an `id` attribute would hold, or nil
    # when there is nothing to verify: no fragment at all, or one of the
    # document-top fragments. Percent-encoding is undone first because the
    # attribute it has to match is stored decoded (`#%EC%95%88` -> `#안`).
    private def checkable_fragment(url : String) : String?
      idx = url.index('#')
      return nil if idx.nil?

      raw = url[(idx + 1)..]
      return nil if raw.empty?
      return nil if raw.compare(TOP_FRAGMENT, case_insensitive: true) == 0

      decoded = begin
        URI.decode(raw)
      rescue
        raw
      end
      decoded.presence
    end

    # A missing anchor is a dead link, so it joins `output` like any other.
    # `status_counts` is left alone on purpose: it is a histogram of HTTP
    # statuses and this URL really did answer 2xx — only `dead` changes, so the
    # coverage percentage reflects the anchor failure.
    #
    # No dedupe guard is needed: `verify_anchors` only ever sees URLs whose
    # status was 2xx, which `record_status` never recorded as dead.
    private def record_dead_anchor(target : String, url : String, options : Options,
                                   output : Hash(String, Array(String)),
                                   coverage_data : Hash(String, TargetCoverage),
                                   mutex : Mutex) : Nil
      mutex.synchronize do
        output[target] ||= [] of String
        output[target] << url

        if options.coverage
          coverage_data[target] ||= TargetCoverage.new
          coverage_data[target].dead += 1
        end
      end
    end
  end
end
