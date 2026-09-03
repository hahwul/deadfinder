require "http/client"
require "uri"
require "lexbor"

module Deadfinder
  # Counting semaphore over a buffered channel: a slot is taken by sending
  # (which blocks once `size` are outstanding) and given back by receiving.
  # No fiber ever holds a slot while waiting on anything else — not on another
  # fiber's in-flight request, not on a second slot — so the pool cannot
  # deadlock no matter how many targets pile up behind it.
  class RequestPermits
    getter size : Int32

    def initialize(size : Int32)
      @size = size < 1 ? 1 : size
      @slots = Channel(Nil).new(@size)
    end

    def acquire(&)
      @slots.send(nil)
      begin
        yield
      ensure
        @slots.receive
      end
    end
  end

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

    # Global cap on concurrent HTTP requests, shared by every target in flight.
    # Target-level concurrency multiplies the number of fibers that *want* to
    # make a request; it must not multiply the number that actually do — ten
    # targets times fifty workers is 500 sockets aimed at one host, which is a
    # self-inflicted DoS rather than throughput. So `-c` means "requests in
    # flight anywhere in the run", and target concurrency rides on top of that
    # fixed budget instead of multiplying it.
    @@permits = RequestPermits.new(1)

    # Requests currently being made, keyed by URL. See `resolve_status`.
    @@inflight = {} of String => Channel(Nil)
    @@shared_mutex = Mutex.new

    # Sized lazily from the run's `-c`. `Runner` is instantiated in several
    # places (and per target on some paths), so the budget cannot live on an
    # instance — every target has to draw from the same pool for the cap to mean
    # anything.
    def self.permits(size : Int32) : RequestPermits
      @@shared_mutex.synchronize do
        permits = @@permits
        return permits if permits.size == size
        @@permits = RequestPermits.new(size)
      end
    end

    # Drops any in-flight bookkeeping left over from a previous run. Only
    # relevant to back-to-back runs in one process (tests, embedded usage).
    def self.reset_shared_state : Nil
      @@shared_mutex.synchronize do
        @@inflight.each_value(&.close)
        @@inflight.clear
      end
    end

    # First backoff step for `--retry`. Doubles per attempt (200ms, 400ms,
    # 800ms, …) and is jittered, so a burst of workers that all trip the same
    # rate limiter does not come back in lockstep and trip it again.
    RETRY_BASE_DELAY = 200.milliseconds

    # Fraction of the computed backoff that jitter may add or remove.
    RETRY_JITTER = 0.25

    # Result of one link check: the status plus whatever `Retry-After` the
    # server attached, which the retry loop honors on a 429/503.
    record CheckOutcome, status : Int32, retry_after : Time::Span?

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
      #
      # The page fetch counts against the same global budget as the link checks
      # below; otherwise `--target-concurrency` would quietly add one extra
      # in-flight request per target on top of `-c`.
      response, final_uri = begin
        Runner.permits(options.concurrency).acquire do
          HttpClient.fetch(uri, options, headers, HttpClient::MAX_REDIRECTS)
        end
      rescue ex
        # A target we cannot reach at all is itself a finding, not just a log
        # line: without this a URL list whose entries all refuse connections
        # reported an empty result. Re-raised so the rescue below still logs it.
        Deadfinder.record_dead_target(target, ERROR_STATUS, options)
        raise ex
      end

      unless response.status.success?
        Deadfinder::Logger.error "Target page returned HTTP #{response.status_code} (links below, if any, come from that response): #{target}"
        # Same reasoning as above for a target that answers but answers badly.
        Deadfinder.record_dead_target(target, response.status_code, options)
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
      # are one request while both still appear in the report. Grouping keeps
      # this target's workers off each other's toes; collisions with *other*
      # targets are handled by the in-flight registry in `resolve_status`.
      grouped = {} of String => Array(String)
      resolved_urls.each do |url|
        (grouped[request_url(url)] ||= [] of String) << url
      end

      jobs = Channel(Tuple(String, Array(String))).new(1000)
      results = Channel(Nil).new(1000)

      # Never spawn more workers than there are requests to make. With several
      # targets in flight the fiber count is multiplied by the number of
      # targets, and a page with three links has no use for fifty idle fibers.
      # (Fewer workers than `-c` costs nothing: the global permit pool, not the
      # per-target pool size, is what bounds concurrency now.)
      worker_count = grouped.size if grouped.size < worker_count

      # Workers log on this target's behalf, so they inherit its output sink
      # (nil unless several targets are being scanned at once) and their lines
      # land inside the target's block instead of racing straight to STDOUT.
      buffer = Deadfinder::Logger.current_buffer

      worker_count.times do |w|
        spawn do
          Deadfinder::Logger.with_buffer(buffer) do
            worker(w, jobs, results, target, options, output, coverage_data, status_cache, mutex)
          end
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
    # connection failure.
    #
    # The cache alone is not enough once targets run concurrently. This used to
    # lean on "within a single target run resolved URLs are unique, so no two
    # workers ever fetch the same URL at once" — an invariant that dies the
    # moment two targets are in flight, because two pages linking to the same
    # URL would both miss the cache and both issue a request before either
    # wrote the result. So a requester publishes an in-flight entry for the URL
    # before fetching; anyone arriving in that window waits on it (holding no
    # permit, so it costs nothing from the request budget) and then re-reads the
    # cache instead of duplicating the request.
    #
    # Only the *final* verdict of `fetch_status_with_retries` is cached. The
    # cache is process-global and never expires, so writing an intermediate
    # failure into it used to mark a URL dead for every remaining page in the
    # run on the strength of a single TCP reset.
    private def resolve_status(url : String, status_cache : Hash(String, Int32),
                               mutex : Mutex, options : Options) : Int32
      # Loop rather than check-once: after waiting on someone else's request the
      # cache is normally populated, but if that fiber's entry vanished without
      # a result (a reset between runs) we fall through and take ownership on
      # the next pass rather than returning a bogus status.
      loop do
        pending = nil

        @@shared_mutex.synchronize do
          if cached = mutex.synchronize { status_cache[url]? }
            return cached
          end
          pending = @@inflight[url]?
          @@inflight[url] = Channel(Nil).new if pending.nil?
        end

        if pending
          # Closed, never sent to: `receive?` returns nil for every waiter at
          # once when the owner finishes.
          pending.receive?
          next
        end

        # This fiber now owns the request for `url`. The `ensure` is what makes
        # that safe: however this ends, the in-flight entry is dropped and its
        # channel closed, or every later requester blocks on a channel nobody
        # will ever close.
        begin
          status = fetch_status_with_retries(url, options)
          # Publish the result before waking the waiters, so they find it in the
          # cache rather than racing back around the loop.
          mutex.synchronize { status_cache[url] = status }
          return status
        ensure
          @@shared_mutex.synchronize { @@inflight.delete(url).try(&.close) }
        end
      end
    end

    # Requests `url` until it answers or the `--retry` budget runs out, and
    # returns the final status. Transient failures back off exponentially with
    # jitter (see `retry_delay`); a definitive answer such as a 404 returns on
    # the first attempt.
    #
    # A permit is held for the request and released before the backoff sleep:
    # holding one while waiting would let a handful of retrying fibers idle the
    # entire `-c` budget and stall every other link in the run.
    private def fetch_status_with_retries(url : String, options : Options) : Int32
      attempts = options.retries < 0 ? 1 : options.retries + 1
      status = ERROR_STATUS
      attempt = 1
      # Set once an attempt has failed outright: from then on `auto` mode skips
      # the HEAD probe, so retrying an unreachable host costs one connect
      # timeout per attempt instead of two.
      force_get = false

      loop do
        retry_after : Time::Span? = nil

        begin
          outcome = Runner.permits(options.concurrency).acquire do
            check_url(url, options, force_get)
          end
          status = outcome.status
          retry_after = outcome.retry_after
        rescue ex
          # Say which attempt this was: without it a retried link logged the
          # same line two or three times and read as several distinct failures.
          if options.verbose
            suffix = attempts > 1 ? " (attempt #{attempt}/#{attempts})" : ""
            Deadfinder::Logger.verbose "[#{ex}]#{suffix} #{url}"
          end
          status = ERROR_STATUS
        end

        force_get = true if status == ERROR_STATUS

        break if attempt >= attempts || !transient?(status)

        wait = retry_delay(attempt, retry_after, options)
        # Hold the whole host back, not just this fiber: every other worker
        # queued on the same origin would otherwise walk straight into the same
        # 429 before this one has finished waiting it out.
        HttpClient.throttle.penalize(origin_key_for(url), wait) if retry_after
        Deadfinder::Logger.debug "Retrying #{url} in #{wait.total_milliseconds.round}ms (attempt #{attempt + 1}/#{attempts}, last status #{status})"
        sleep wait

        attempt += 1
      end

      status
    end

    # Conditions worth another attempt: the request never produced a status, the
    # server said "too many requests", or it reported a server-side fault. A 404
    # — or any other 4xx — is a definitive answer about the link and is never
    # retried, so a genuinely dead link still costs exactly one request.
    private def transient?(status : Int32) : Bool
      status == ERROR_STATUS || status == 429 || (status >= 500 && status <= 599)
    end

    # Exponential backoff with +/-`RETRY_JITTER` jitter, raised to the server's
    # `Retry-After` when it asked for longer. Bounded by `--timeout` so a
    # hostile (or absurd) `Retry-After: 86400` cannot park the run for a day.
    private def retry_delay(attempt : Int32, retry_after : Time::Span?, options : Options) : Time::Span
      backoff = RETRY_BASE_DELAY * (1 << Math.min(attempt - 1, 16))
      jitter = 1.0 + (Random.rand * 2.0 - 1.0) * RETRY_JITTER
      wait = backoff * jitter
      wait = retry_after if retry_after && retry_after > wait

      cap = options.timeout.seconds
      wait > cap ? cap : wait
    end

    # Origin of `url` for throttling purposes; a URL that no longer parses just
    # doesn't get a host-wide penalty.
    private def origin_key_for(url : String) : String
      HttpClient.origin_key(URI.parse(url))
    rescue
      url
    end

    # Checks a single link. Redirects are deliberately *not* followed here: the
    # 30x status is itself the reported result (`--include30x`). The request
    # method comes from `--method`; see `HttpClient::METHOD_AUTO` for why the
    # default confirms an unhappy HEAD with a GET before reporting anything.
    private def check_url(url : String, options : Options, force_get : Bool = false) : CheckOutcome
      uri = URI.parse(url)
      headers = build_headers(options.worker_headers, options.user_agent)
      response = HttpClient.check(uri, options, headers, force_get)
      # `Retry-After` is only meaningful on the statuses that define it; reading
      # it elsewhere would let an unrelated header stretch the backoff.
      retry_after = if response.status_code == 429 || response.status_code == 503
                      HttpClient.parse_retry_after(response.headers["Retry-After"]?)
                    end
      CheckOutcome.new(response.status_code, retry_after)
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
      dead = dead_status?(status_code, options)
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

    # Dead/alive policy, in strict precedence order:
    #
    #   1. `--accept-status` — an explicit allow-list always wins, so a code
    #      listed there is alive even when it also appears in `--dead-status`.
    #      This is the escape hatch for bot-defense answers that are not really
    #      broken links: LinkedIn's 999, Cloudflare's 403 to a non-browser
    #      User-Agent, a 429 from a rate limiter.
    #   2. `--dead-status` / `--exclude-status` — anything listed is dead, even
    #      a 2xx (e.g. a soft-404 page that answers 200).
    #   3. the built-in default, unchanged: >= 400 is dead, and 3xx is dead only
    #      when `--include30x` is set.
    private def dead_status?(status_code : Int32, options : Options) : Bool
      return false if StatusList.includes?(options.accept_status_ranges, status_code)
      return true if StatusList.includes?(options.dead_status_ranges, status_code)
      status_code >= 400 || (status_code >= 300 && options.include30x)
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
      worker_count = pending.size if pending.size < worker_count
      jobs = Channel(Tuple(String, Array(Tuple(String, String)))).new(1000)
      results = Channel(Nil).new(1000)

      # Same as the link-check pass: these fibers log on the target's behalf, so
      # they inherit its output buffer and their findings land inside the
      # target's block instead of racing other targets straight to the sink.
      buffer = Deadfinder::Logger.current_buffer

      worker_count.times do
        spawn do
          Deadfinder::Logger.with_buffer(buffer) do
            anchor_worker(jobs, results, target, options, output, coverage_data, mutex)
          end
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
      # Counts against the global in-flight budget like any other request;
      # without this `--check-anchors` would quietly exceed `-c`.
      response, _ = Runner.permits(options.concurrency).acquire do
        HttpClient.fetch(uri, options, headers)
      end
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
