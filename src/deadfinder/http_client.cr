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
      host = uri.host.not_nil!
      port = uri.port
      use_ssl = uri.scheme == "https"

      proxy_str = options.proxy
      if !proxy_str.empty?
        proxy_uri = resolve_proxy(proxy_str)

        if proxy_uri && proxy_uri.host
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
            # HTTPS through proxy: use CONNECT tunnel
            target_port = port || 443
            socket = TCPSocket.new(proxy_host, proxy_port)
            socket.read_timeout = options.timeout.seconds

            connect_request = "CONNECT #{host}:#{target_port} HTTP/1.1\r\nHost: #{host}:#{target_port}\r\n"
            connect_request += "Proxy-Authorization: #{auth_header}\r\n" if auth_header
            connect_request += "\r\n"
            socket.print(connect_request)

            response_line = socket.gets
            unless response_line && response_line.includes?("200")
              socket.close
              raise "Proxy CONNECT to #{host}:#{target_port} via #{proxy_host}:#{proxy_port} failed: #{response_line.try(&.strip) || "no response"}"
            end
            # Consume remaining headers
            while (line = socket.gets) && !line.strip.empty?
            end

            tls_socket = OpenSSL::SSL::Socket::Client.new(socket, context: ssl_context(options), hostname: host)
            client = HTTP::Client.new(io: tls_socket, host: host, port: target_port)
            client.read_timeout = options.timeout.seconds
            return client
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
          begin
            parsed = URI.parse(proxy_str)
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
