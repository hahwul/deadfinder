require "http/client"
require "openssl"
require "uri"
require "base64"
require "socket"
require "compress/gzip"

module Deadfinder
  module HttpClient
    # Redirect hops followed when fetching a *document* (a scan target page or a
    # sitemap). Link status checks deliberately pass 0: there the 30x status is
    # the answer being reported (see `--include30x`).
    MAX_REDIRECTS = 5

    # Headers that must not be replayed to a different origin after a redirect.
    # Mirrors curl's default behaviour: following a redirect off-host with a
    # user-supplied `Authorization`/`Cookie` would leak the credential.
    CROSS_ORIGIN_SENSITIVE_HEADERS = ["Authorization", "Cookie", "Proxy-Authorization"]

    # `--method` values. These select the HTTP method used for a *link status
    # check*; documents (the scan target page, a sitemap) are always fetched
    # with GET because their body is what the caller wants.
    #
    #   auto (default) — send a HEAD first, and re-issue the check as a GET
    #                    whenever that HEAD answer cannot be trusted. "Cannot be
    #                    trusted" means any status >= 400 (which covers the
    #                    405/501 "method not supported" pair, the CDNs and app
    #                    servers that answer HEAD with a 403/404/500 while GET is
    #                    fine, and bot-defense codes such as LinkedIn's 999) as
    #                    well as any transport-level failure of the HEAD itself.
    #                    A link is therefore never reported dead on the strength
    #                    of a HEAD alone — a GET always confirms it.
    #   head           — HEAD only. Cheapest, but takes the server's HEAD answer
    #                    at face value, so it can produce false positives.
    #   get            — GET only. The pre-2.1 behaviour: always downloads the
    #                    body just to read the status line.
    METHOD_AUTO = "auto"
    METHOD_HEAD = "head"
    METHOD_GET  = "get"

    METHODS = [METHOD_AUTO, METHOD_HEAD, METHOD_GET]

    # In `auto` mode a HEAD response at or above this status is not trusted and
    # is confirmed with a GET before it can be reported.
    HEAD_UNTRUSTED_STATUS = 400

    # Transport failures that mean the host was never reached at all. A GET
    # cannot succeed where the TCP connect timed out, was refused, or the name
    # did not resolve, so `auto` must not spend a second full timeout proving
    # it — that turned one connect timeout per unreachable link into four
    # (HEAD + GET on the first attempt, then one GET per retry). Any *other*
    # failure (a reset mid-response, a read timeout after the connection was
    # established) still earns a GET: those can be HEAD-specific.
    UNREACHABLE_ERRORS = {Socket::ConnectError, Socket::Addrinfo::Error, IO::TimeoutError}

    @@proxy_cache = {} of String => URI?
    @@proxy_cache_mutex = Mutex.new

    # Monotonic clock reads for the pool and the throttle. Wall-clock time is
    # the wrong source here: an NTP step or a DST change would make an idle
    # connection look fresh forever, or a throttle slot unreachable.
    #
    # Crystal 1.21 renamed `Time.monotonic` to `Time.instant` and deprecated the
    # old spelling, but shard.yml still supports 1.19.1 where `Time.instant`
    # does not exist. Pick the available one at compile time rather than force a
    # compiler floor bump for a clock read.
    {% if Time.class.has_method?("instant") %}
      alias MonotonicTime = Time::Instant

      def self.monotonic_now : MonotonicTime
        Time.instant
      end
    {% else %}
      alias MonotonicTime = Time::Span

      def self.monotonic_now : MonotonicTime
        Time.monotonic
      end
    {% end %}

    # Bounded pool of idle keep-alive clients, keyed by origin (plus the
    # connection settings that shape the client, so a differently-configured run
    # can never pick up a client built for the previous one).
    #
    # Borrow/return, not share: `checkout` *removes* the client from the pool,
    # so it is invisible to every other fiber until `checkin` puts it back.
    # That exclusivity is the whole point — Crystal fibers yield on every socket
    # read, so two fibers holding one `HTTP::Client` would interleave their
    # requests on a single connection and read each other's responses.
    class ConnectionPool
      # Idle clients kept per origin. Chosen to sit above the default
      # concurrency (50) so a single-host scan — the case the pool exists for —
      # reuses every worker's connection instead of re-handshaking most of them.
      MAX_IDLE_PER_ORIGIN = 64

      # Idle clients kept across *all* origins. A scan whose links fan out over
      # hundreds of hosts would otherwise retain a few sockets per host and run
      # the process out of file descriptors; past this point the least recently
      # used connection is closed to make room.
      MAX_IDLE_TOTAL = 64

      # Servers close idle keep-alive connections after a few seconds. Handing
      # out one the peer already dropped costs a failed request plus a
      # reconnect, so anything idle longer than this is closed on borrow.
      MAX_IDLE_AGE = 20.seconds

      record Entry, client : HTTP::Client, idle_since : MonotonicTime

      def initialize
        # Per origin, oldest first: entries are appended on check-in and taken
        # from the end, so the front of each bucket is that origin's stalest
        # connection and the natural eviction candidate.
        @idle = {} of String => Array(Entry)
        @total = 0
        @mutex = Mutex.new
      end

      # Returns a client the caller now owns exclusively, or nil when the pool
      # has nothing fresh for this origin.
      def checkout(key : String) : HTTP::Client?
        expired = [] of HTTP::Client
        client = nil
        @mutex.synchronize do
          if entries = @idle[key]?
            now = HttpClient.monotonic_now
            while entry = entries.pop?
              @total -= 1
              if now - entry.idle_since <= MAX_IDLE_AGE
                client = entry.client
                break
              end
              expired << entry.client
            end
            @idle.delete(key) if entries.empty?
          end
        end
        # Closed outside the lock: a socket close must not serialize every other
        # fiber looking for a connection.
        expired.each { |stale| close_quietly(stale) }
        client
      end

      def checkin(key : String, client : HTTP::Client) : Nil
        evicted = [] of HTTP::Client
        @mutex.synchronize do
          entries = (@idle[key] ||= [] of Entry)
          if entries.size >= MAX_IDLE_PER_ORIGIN
            evicted << client
            @idle.delete(key) if entries.empty?
          else
            entries << Entry.new(client, HttpClient.monotonic_now)
            @total += 1
            while @total > MAX_IDLE_TOTAL && (oldest = take_oldest)
              evicted << oldest
            end
          end
        end
        evicted.each { |stale| close_quietly(stale) }
      end

      # A client whose request raised is never returned to the pool: the
      # connection may be half-written or half-read, and reusing it would
      # desynchronize the next response.
      def discard(client : HTTP::Client) : Nil
        close_quietly(client)
      end

      def close_all : Nil
        clients = [] of HTTP::Client
        @mutex.synchronize do
          @idle.each_value { |entries| entries.each { |entry| clients << entry.client } }
          @idle.clear
          @total = 0
        end
        clients.each { |client| close_quietly(client) }
      end

      def idle_count(key : String) : Int32
        @mutex.synchronize { @idle[key]?.try(&.size) || 0 }
      end

      def total_idle : Int32
        @mutex.synchronize { @total }
      end

      # Removes and returns the globally least recently used idle client, or nil
      # when nothing is pooled. The caller must already hold the lock.
      private def take_oldest : HTTP::Client?
        oldest_key : String? = nil
        oldest_at : MonotonicTime? = nil

        @idle.each do |candidate_key, entries|
          front = entries.first?
          next unless front
          current = oldest_at
          if current.nil? || front.idle_since < current
            oldest_at = front.idle_since
            oldest_key = candidate_key
          end
        end

        key = oldest_key
        return nil unless key
        entries = @idle[key]
        entry = entries.shift
        @idle.delete(key) if entries.empty?
        @total -= 1
        entry.client
      end

      private def close_quietly(client : HTTP::Client) : Nil
        client.close
      rescue
        # Already closed / reset by the peer; nothing left to clean up.
      end
    end

    # Per-host minimum interval between requests (`--delay`). Keyed by host so a
    # slow or throttled host only ever delays the fibers that are talking to it.
    #
    # Slots are reserved rather than measured after the fact: each caller claims
    # the next free instant for its host and sleeps until then, so N fibers
    # racing on one host end up spaced `delay` apart instead of all waking at
    # once and firing together.
    class HostThrottle
      def initialize
        @next_slot = {} of String => MonotonicTime
        @mutex = Mutex.new
        @penalized = false
      end

      def acquire(key : String, delay : Time::Span) : Nil
        # Fast path for the default configuration: with no `--delay` and no
        # `Retry-After` ever collected there is nothing to coordinate, so a run
        # does not pay a lock per request. `@penalized` is only ever flipped on,
        # and a stale `true` merely routes through the (correct) slow path.
        return if delay <= Time::Span.zero && !@penalized

        wait = @mutex.synchronize do
          now = HttpClient.monotonic_now
          slot = @next_slot[key]?
          if slot.nil? || slot <= now
            # Claiming a slot is what spaces requests out; with no delay there
            # is nothing to claim, and the entry is left alone so the map does
            # not grow one key per host for nothing.
            @next_slot[key] = now + delay if delay > Time::Span.zero
            Time::Span.zero
          else
            @next_slot[key] = slot + delay
            slot - now
          end
        end

        sleep wait if wait > Time::Span.zero
      end

      # Pushes a host's next free slot out by `span`, so a `Retry-After` earned
      # by one fiber also holds back every other fiber queued on that host
      # instead of each of them having to collect its own 429 first.
      def penalize(key : String, span : Time::Span) : Nil
        return if span <= Time::Span.zero
        @mutex.synchronize do
          until_time = HttpClient.monotonic_now + span
          slot = @next_slot[key]?
          @next_slot[key] = until_time if slot.nil? || slot < until_time
          @penalized = true
        end
      end

      def reset : Nil
        @mutex.synchronize do
          @next_slot.clear
          @penalized = false
        end
      end
    end

    @@pool = ConnectionPool.new
    @@throttle = HostThrottle.new

    def self.pool : ConnectionPool
      @@pool
    end

    def self.throttle : HostThrottle
      @@throttle
    end

    # Drops every pooled connection. Only needed when a process performs several
    # independent runs (specs, embedded usage); a one-shot CLI run just exits.
    def self.close_idle_connections : Nil
      @@pool.close_all
      @@throttle.reset
    end

    # Origin identity used for both throttling and pooling: two URLs share a
    # connection only when scheme, host and effective port all match.
    def self.origin_key(uri : URI) : String
      "#{uri.scheme}://#{uri.host}:#{effective_port(uri)}"
    end

    # Parses a `Retry-After` header in either of its two RFC 9110 forms —
    # delta-seconds ("120") or an HTTP-date ("Wed, 21 Oct 2015 07:28:00 GMT").
    # Returns nil when the header is absent or unparseable, and clamps a past
    # date to zero so a stale header cannot produce a negative sleep.
    def self.parse_retry_after(value : String?) : Time::Span?
      raw = value.try(&.strip)
      return nil if raw.nil? || raw.empty?

      if seconds = raw.to_i?
        return seconds < 0 ? Time::Span.zero : seconds.seconds
      end

      if time = HTTP.parse_time(raw)
        span = time - Time.utc
        return span < Time::Span.zero ? Time::Span.zero : span
      end

      nil
    end

    # Parse "Name: value" header strings. Accepts ":" or ": " as the
    # separator and trims both sides — every request the tool makes (target
    # page, sitemap document, link check) builds its headers here so users
    # don't hit depending-on-which-flag surprises.
    def self.build_headers(raw : Array(String), user_agent : String) : HTTP::Headers
      headers = HTTP::Headers.new
      raw.each do |header|
        name, sep, value = header.partition(':')
        next if sep.empty?
        name = name.strip
        next if name.empty?
        headers[name] = value.strip
      end
      # Honor a user-supplied User-Agent (HTTP::Headers is case-insensitive);
      # only fall back to the default when none was provided.
      headers["User-Agent"] = user_agent unless headers.has_key?("User-Agent")
      headers
    end

    def self.create(uri : URI, options : Options) : HTTP::Client
      # `presence` (not just `nil?`): `file:///etc/hosts` parses to an *empty*
      # host, which passed a nil-check and then tried to connect to ":80".
      host = uri.host.presence
      if host.nil?
        raise ArgumentError.new("missing host - did you include the scheme (http:// or https://)?")
      end
      scheme = uri.scheme
      # Anything other than http/https cannot be fetched here; without this
      # guard `ftp://host/x` was silently requested as plain HTTP on port 80.
      unless scheme == "http" || scheme == "https"
        raise ArgumentError.new("Unsupported URL scheme: #{scheme || "(none)"} (only http and https are supported)")
      end
      port = uri.port
      use_ssl = scheme == "https"

      proxy_str = options.proxy
      if !proxy_str.empty?
        proxy_uri = resolve_proxy(proxy_str)

        if proxy_uri && proxy_uri.host
          proxy_scheme = proxy_uri.scheme
          if proxy_scheme && proxy_scheme != "http" && proxy_scheme != "https"
            raise ArgumentError.new("Unsupported proxy scheme: #{proxy_scheme} (only http and https proxies are supported)")
          end

          proxy_host = proxy_uri.host.not_nil!
          proxy_port = proxy_uri.port || (proxy_uri.scheme == "https" ? 443 : 8080)
          proxy_user = proxy_uri.user
          proxy_password = proxy_uri.password

          # Apply proxy_auth option if provided
          if !options.proxy_auth.empty?
            parts = options.proxy_auth.split(":", 2)
            if parts.size == 2
              proxy_user = parts[0]
              proxy_password = parts[1]
            end
          end

          auth_header = if proxy_user && proxy_password
                          "Basic #{Base64.strict_encode("#{proxy_user}:#{proxy_password}")}"
                        else
                          nil
                        end

          if use_ssl
            # HTTPS through proxy: use CONNECT tunnel.
            # Bound DNS resolution and the TCP connect by the configured timeout
            # so an unreachable/firewalled proxy raises instead of hanging for
            # the full kernel TCP timeout (these are unset on TCPSocket.new by
            # default, unlike the direct and HTTP-proxy paths).
            target_port = port || 443
            socket = TCPSocket.new(proxy_host, proxy_port,
              dns_timeout: options.timeout.seconds,
              connect_timeout: options.timeout.seconds)
            begin
              socket.read_timeout = options.timeout.seconds
              socket.write_timeout = options.timeout.seconds

              connect_request = "CONNECT #{host}:#{target_port} HTTP/1.1\r\nHost: #{host}:#{target_port}\r\n"
              connect_request += "Proxy-Authorization: #{auth_header}\r\n" if auth_header
              connect_request += "\r\n"
              socket.print(connect_request)

              response_line = socket.gets
              # Accept only a real "200" status token, not any status line that
              # merely contains the substring "200" (e.g. a 502 reason phrase or
              # a trace id) — which would otherwise proceed to a TLS handshake
              # over an un-tunneled socket and surface a misleading error.
              status_parts = response_line.try(&.split)
              unless status_parts && status_parts.size >= 2 && status_parts[1] == "200"
                raise "Proxy CONNECT to #{host}:#{target_port} via #{proxy_host}:#{proxy_port} failed: #{response_line.try(&.strip) || "no response"}"
              end
              # Consume remaining headers
              while (line = socket.gets) && !line.strip.empty?
              end

              tls_socket = OpenSSL::SSL::Socket::Client.new(socket, context: ssl_context(options), hostname: host)
              client = HTTP::Client.new(io: tls_socket, host: host, port: target_port)
              client.read_timeout = options.timeout.seconds
              return client
            rescue ex
              socket.close
              raise ex
            end
          else
            # HTTP through proxy: connect to proxy, use absolute URI in requests
            client = HTTP::Client.new(proxy_host, port: proxy_port)
            client.read_timeout = options.timeout.seconds
            client.connect_timeout = options.timeout.seconds
            if auth_header
              client.before_request do |request|
                request.headers["Proxy-Authorization"] = auth_header.not_nil!
              end
            end
            return client
          end
        end
      end

      create_direct(host, port, use_ssl, options)
    end

    # For HTTP proxy, requests need to use absolute URI as path
    def self.absolute_uri(uri : URI) : String
      uri.to_s
    end

    def self.proxy_configured?(options : Options) : Bool
      !options.proxy.empty?
    end

    # Request-line target for `uri`: an absolute URI when talking plain HTTP to
    # a forward proxy, an origin-form path otherwise.
    def self.request_path(uri : URI, options : Options) : String
      if proxy_configured?(options) && uri.scheme == "http"
        absolute_uri(uri)
      else
        path = uri.path.presence || "/"
        if q = uri.query.presence
          "#{path}?#{q}"
        else
          path
        end
      end
    end

    # Runs a single link status check against `uri`, honoring `--method`.
    # Redirects are never followed here: the 30x status is itself the reported
    # result (`--include30x`), which is why every call passes 0 hops.
    #
    # `force_get` is set by the retry loop once an attempt for this URL has
    # already failed at the transport level: the HEAD probe has nothing left to
    # prove there, and re-running it would make every retry of an unreachable
    # host pay two connect timeouts instead of one.
    def self.check(uri : URI, options : Options, headers : HTTP::Headers,
                   force_get : Bool = false) : HTTP::Client::Response
      case options.http_method
      when METHOD_GET
        fetch(uri, options, headers, 0, "GET").first
      when METHOD_HEAD
        fetch(uri, options, headers, 0, "HEAD").first
      else
        return fetch(uri, options, headers, 0, "GET").first if force_get

        # `auto`: HEAD first, GET whenever the HEAD answer is untrustworthy —
        # see METHOD_AUTO for why a HEAD is never allowed to condemn a link.
        head_response = begin
          fetch(uri, options, headers, 0, "HEAD").first
        rescue ex
          # The host was never reached, so there is nothing a GET could add and
          # a great deal of time it could waste. Propagate; the caller's retry
          # loop already re-attempts with GET (see `force_get`).
          raise ex if UNREACHABLE_ERRORS.includes?(ex.class)
          # Anything else told us nothing about the *link*, only about HEAD, so
          # this is not yet a failure to report.
          Deadfinder::Logger.debug "HEAD failed for #{uri} (#{ex.message}); confirming with GET"
          nil
        end

        if head_response && head_response.status_code < HEAD_UNTRUSTED_STATUS
          head_response
        else
          fetch(uri, options, headers, 0, "GET").first
        end
      end
    end

    # Fetches `uri` with `method` and returns the response together with the URI
    # it was finally served from. `max_redirects` hops of 30x `Location` are
    # followed; with the default of 0 the redirect response itself is returned
    # untouched.
    #
    # Callers need the final URI because relative links (and relative sitemap
    # `<loc>` entries) must resolve against the post-redirect location, not
    # against the address the user originally typed.
    def self.fetch(uri : URI, options : Options, headers : HTTP::Headers,
                   max_redirects : Int32 = 0,
                   method : String = "GET") : {HTTP::Client::Response, URI}
      current = uri
      current_headers = headers
      seen = Set(String).new
      hops = 0

      loop do
        response = request_once(current, options, current_headers, method)

        return {response, current} if hops >= max_redirects || !response.status.redirection?

        location = response.headers["Location"]?.try(&.strip).presence
        # A 3xx without a usable Location (300 Multiple Choices, 304 Not
        # Modified, or a malformed response) is the final answer.
        return {response, current} unless location

        next_uri = begin
          current.resolve(location)
        rescue
          return {response, current}
        end
        return {response, current} unless next_uri.scheme == "http" || next_uri.scheme == "https"
        return {response, current} unless next_uri.host

        # Stop on a redirect loop rather than burning every remaining hop.
        seen << current.to_s
        return {response, current} if seen.includes?(next_uri.to_s)

        current_headers = strip_cross_origin_headers(current_headers, current, next_uri)
        current = next_uri
        hops += 1
      end
    end

    # Issues exactly one request, borrowing a pooled connection when the current
    # configuration allows it and always leaving the pool in a consistent state:
    # a client whose request raised is discarded, never handed to another fiber.
    private def self.request_once(uri : URI, options : Options,
                                  headers : HTTP::Headers, method : String) : HTTP::Client::Response
      # Space requests to this host per `--delay` before a connection is even
      # borrowed, so a queued fiber does not sit on a pooled client while it
      # waits out its slot.
      key = origin_key(uri)
      @@throttle.acquire(key, options.delay.milliseconds)

      poolable = poolable?(options)
      pool_key = poolable ? pool_key(uri, options) : nil

      client = (pool_key ? @@pool.checkout(pool_key) : nil) || create(uri, options)

      begin
        response = client.exec(method, request_path(uri, options), headers: headers)
      rescue ex
        # The connection may be half-written or half-read; reusing it would
        # desynchronize the next response, so it never goes back to the pool.
        # A peer that closed an idle keep-alive socket needs no handling here:
        # `HTTP::Client#exec` reconnects transparently in that case.
        if pool_key
          @@pool.discard(client)
        else
          close_quietly(client)
        end
        raise ex
      end

      if pool_key && response.keep_alive?
        @@pool.checkin(pool_key, client)
      elsif pool_key
        # `Connection: close` — the server is done with this socket.
        @@pool.discard(client)
      else
        close_quietly(client)
      end

      response
    end

    # Only plain direct connections are pooled. With a proxy configured the
    # HTTPS path builds a client on top of a hand-rolled CONNECT tunnel whose
    # lifecycle this pool does not model, and the HTTP path aims every client at
    # the proxy rather than at the origin the pool is keyed by — so both are left
    # to the old create-and-close behaviour. Correctness over coverage.
    private def self.poolable?(options : Options) : Bool
      !proxy_configured?(options)
    end

    # Pool identity: the origin, plus every option that changes how the
    # connection itself is built. A client created under one timeout/TLS
    # configuration must never be reused under another.
    private def self.pool_key(uri : URI, options : Options) : String
      "#{origin_key(uri)}|t=#{options.timeout}|k=#{options.insecure}"
    end

    private def self.close_quietly(client : HTTP::Client) : Nil
      client.close
    rescue
      # Already closed or reset by the peer.
    end

    # Sitemaps are routinely published gzipped (`sitemap.xml.gz`). When the file
    # is served as an opaque `application/gzip` body there is no
    # `Content-Encoding` for HTTP::Client to transparently undo, so detect the
    # gzip magic bytes and inflate here. Returns the body unchanged when it is
    # not gzip, or when it cannot be inflated.
    def self.decompress_if_gzip(body : String) : String
      bytes = body.to_slice
      return body unless bytes.size >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b

      begin
        Compress::Gzip::Reader.open(IO::Memory.new(bytes)) do |gz|
          gz.gets_to_end
        end
      rescue ex
        Deadfinder::Logger.debug "Gzip decompression failed: #{ex.message}"
        body
      end
    end

    private def self.strip_cross_origin_headers(headers : HTTP::Headers, from : URI, to : URI) : HTTP::Headers
      return headers if same_origin?(from, to)
      return headers unless CROSS_ORIGIN_SENSITIVE_HEADERS.any? { |name| headers.has_key?(name) }

      # Build a fresh instance rather than duplicating: HTTP::Headers is a
      # struct wrapping a Hash, so `dup` would share that Hash and deleting
      # from the copy would strip the caller's headers too.
      stripped = HTTP::Headers.new
      headers.each do |name, values|
        next if CROSS_ORIGIN_SENSITIVE_HEADERS.any? { |sensitive| name.compare(sensitive, case_insensitive: true) == 0 }
        values.each { |value| stripped.add(name, value) }
      end
      stripped
    end

    private def self.same_origin?(a : URI, b : URI) : Bool
      a.scheme == b.scheme && a.host == b.host && effective_port(a) == effective_port(b)
    end

    private def self.effective_port(uri : URI) : Int32
      uri.port || (uri.scheme == "https" ? 443 : 80)
    end

    private def self.create_direct(host : String, port : Int32?, use_ssl : Bool, options : Options) : HTTP::Client
      client = HTTP::Client.new(host, port: port, tls: use_ssl ? ssl_context(options) : nil)
      client.read_timeout = options.timeout.seconds
      client.connect_timeout = options.timeout.seconds
      client
    end

    private def self.resolve_proxy(proxy_str : String) : URI?
      @@proxy_cache_mutex.synchronize do
        if @@proxy_cache.has_key?(proxy_str)
          @@proxy_cache[proxy_str]
        else
          # Accept a bare "host:port" (e.g. Burp's default 127.0.0.1:8080):
          # without a scheme URI.parse yields a nil host and the proxy would be
          # silently ignored, sending traffic directly. Default to an http proxy.
          normalized = proxy_str.includes?("://") ? proxy_str : "http://#{proxy_str}"
          begin
            parsed = URI.parse(normalized)
            @@proxy_cache[proxy_str] = parsed
            parsed
          rescue ex
            Deadfinder::Logger.error "Invalid proxy URI: #{proxy_str} - #{ex.message}"
            @@proxy_cache[proxy_str] = nil
            nil
          end
        end
      end
    end

    private def self.ssl_context(options : Options) : OpenSSL::SSL::Context::Client
      ctx = OpenSSL::SSL::Context::Client.new
      ctx.verify_mode = options.insecure ? OpenSSL::SSL::VerifyMode::NONE : OpenSSL::SSL::VerifyMode::PEER
      ctx
    end
  end
end
