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

    @@proxy_cache = {} of String => URI?
    @@proxy_cache_mutex = Mutex.new

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

    # Fetches `uri` and returns the response together with the URI it was
    # finally served from. `max_redirects` hops of 30x `Location` are followed;
    # with the default of 0 the redirect response itself is returned untouched.
    #
    # Callers need the final URI because relative links (and relative sitemap
    # `<loc>` entries) must resolve against the post-redirect location, not
    # against the address the user originally typed.
    def self.fetch(uri : URI, options : Options, headers : HTTP::Headers,
                   max_redirects : Int32 = 0) : {HTTP::Client::Response, URI}
      current = uri
      current_headers = headers
      seen = Set(String).new
      hops = 0

      loop do
        client = create(current, options)
        response = begin
          client.get(request_path(current, options), headers: current_headers)
        ensure
          client.close
        end

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
