require "http/client"
require "openssl"
require "uri"

module Deadfinder
  module HttpClient
    def self.create(uri : URI, options : Options) : HTTP::Client
      host = uri.host.not_nil!
      port = uri.port
      use_ssl = uri.scheme == "https"

      client = HTTP::Client.new(host, port: port, tls: use_ssl ? ssl_context : nil)
      client.read_timeout = options.timeout.seconds
      client.connect_timeout = options.timeout.seconds
      client
    end

    private def self.ssl_context : OpenSSL::SSL::Context::Client
      ctx = OpenSSL::SSL::Context::Client.new
      ctx.verify_mode = OpenSSL::SSL::VerifyMode::NONE
      ctx
    end
  end
end
