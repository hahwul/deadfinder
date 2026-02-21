# frozen_string_literal: true

require 'net/http'
require 'openssl'

module DeadFinder
  # HTTP client module
  module HttpClient
    @proxy_cache = {}
    @proxy_cache_mutex = Mutex.new

    def self.create(uri, options)
      proxy_str = options['proxy']
      proxy_uri = nil

      if proxy_str && !proxy_str.empty?
        proxy_uri = if @proxy_cache.key?(proxy_str)
                      @proxy_cache[proxy_str]
                    else
                      @proxy_cache_mutex.synchronize do
                        @proxy_cache[proxy_str] ||= begin
                          URI.parse(proxy_str)
                        rescue URI::InvalidURIError => e
                          DeadFinder::Logger.error "Invalid proxy URI: #{proxy_str} - #{e.message}"
                          nil
                        end
                      end
                    end
      end
      http = if proxy_uri
               Net::HTTP.new(uri.host, uri.port,
                             proxy_uri.host, proxy_uri.port,
                             proxy_uri.user, proxy_uri.password)
             else
               Net::HTTP.new(uri.host, uri.port)
             end
      http.use_ssl = (uri.scheme == 'https')
      http.read_timeout = options['timeout'].to_i if options['timeout']
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE if http.use_ssl?

      if options['proxy_auth'] && proxy_uri
        proxy_user, proxy_pass = options['proxy_auth'].split(':', 2)
        http.proxy_user = proxy_user
        http.proxy_pass = proxy_pass
      end

      http
    end
  end
end
