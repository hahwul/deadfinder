# frozen_string_literal: true

require 'net/http'
require 'openssl'

module DeadFinder
  # HTTP client module
  module HttpClient
    def self.create(uri, options)
      proxy_uri = parse_proxy_uri(options['proxy'])
      http = create_http_connection(uri, proxy_uri)
      configure_http(http, uri, options)
      configure_proxy_auth(http, options['proxy_auth']) if proxy_uri
      http
    end

    def self.parse_proxy_uri(proxy)
      return nil if proxy.nil? || proxy.empty?

      URI.parse(proxy)
    rescue URI::InvalidURIError => e
      DeadFinder::Logger.error "Invalid proxy URI: #{proxy} - #{e.message}"
      nil
    end

    def self.create_http_connection(uri, proxy_uri)
      if proxy_uri
        Net::HTTP.new(uri.host, uri.port,
                      proxy_uri.host, proxy_uri.port,
                      proxy_uri.user, proxy_uri.password)
      else
        Net::HTTP.new(uri.host, uri.port)
      end
    end

    def self.configure_http(http, uri, options)
      http.use_ssl = (uri.scheme == 'https')
      http.read_timeout = options['timeout'].to_i if options['timeout']
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE if http.use_ssl?
    end

    def self.configure_proxy_auth(http, proxy_auth)
      return unless proxy_auth

      proxy_user, proxy_pass = proxy_auth.split(':', 2)
      http.proxy_user = proxy_user
      http.proxy_pass = proxy_pass
    end
  end
end
