require "http/client"
require "openssl"
require "uri"
require "base64"
require "socket"

module Deadfinder
  module HttpClient
    @@proxy_cache = {} of String => URI?
    @@proxy_cache_mutex = Mutex.new

    def self.create(uri : URI, options : Options) : HTTP::Client
      host = uri.host
      if host.nil?
        raise ArgumentError.new("URI is missing a host")
      end
      port = uri.port
      use_ssl = uri.scheme == "https"

      proxy_str = options.proxy
      if !proxy_str.empty?
        proxy_uri = resolve_proxy(proxy_str)

        if proxy_uri && proxy_uri.host
          scheme = proxy_uri.scheme
          if scheme && scheme != "http" && scheme != "https"
            raise ArgumentError.new("Unsupported proxy scheme: #{scheme} (only http and https proxies are supported)")
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
