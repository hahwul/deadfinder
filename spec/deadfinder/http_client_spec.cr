require "../spec_helper"

describe Deadfinder::HttpClient do
  before_each do
    reset_deadfinder_state
  end

  describe ".create" do
    it "creates a basic HTTP client" do
      uri = URI.parse("http://example.com")
      options = default_test_options
      client = Deadfinder::HttpClient.create(uri, options)
      client.should be_a(HTTP::Client)
    end

    it "creates an HTTPS client with SSL" do
      uri = URI.parse("https://example.com")
      options = default_test_options
      client = Deadfinder::HttpClient.create(uri, options)
      client.should be_a(HTTP::Client)
    end

    it "creates client with custom timeout without error" do
      uri = URI.parse("http://example.com")
      options = default_test_options
      options.timeout = 5
      client = Deadfinder::HttpClient.create(uri, options)
      client.should be_a(HTTP::Client)
    end

    it "returns a usable client for a scheme-less proxy string" do
      uri = URI.parse("http://example.com")
      options = default_test_options
      options.proxy = "not-a-valid-proxy"
      client = Deadfinder::HttpClient.create(uri, options)
      client.should be_a(HTTP::Client)
    end

    it "accepts a bare host:port proxy by defaulting to http" do
      uri = URI.parse("http://example.com")
      options = default_test_options
      options.proxy = "127.0.0.1:8080"
      client = Deadfinder::HttpClient.create(uri, options)
      client.should be_a(HTTP::Client)
    end

    it "raises for an unsupported (non-http) proxy scheme" do
      uri = URI.parse("https://example.com")
      options = default_test_options
      options.proxy = "socks5://127.0.0.1:1080"
      expect_raises(ArgumentError, /Unsupported proxy scheme/) do
        Deadfinder::HttpClient.create(uri, options)
      end
    end

    it "creates client without proxy when proxy is empty" do
      uri = URI.parse("http://example.com")
      options = default_test_options
      options.proxy = ""
      client = Deadfinder::HttpClient.create(uri, options)
      client.should be_a(HTTP::Client)
    end

    it "creates an HTTPS client when insecure flag is enabled" do
      uri = URI.parse("https://example.com")
      options = default_test_options
      options.insecure = true
      client = Deadfinder::HttpClient.create(uri, options)
      client.should be_a(HTTP::Client)
    end

    it "creates an HTTPS client with verification enabled by default" do
      uri = URI.parse("https://example.com")
      options = default_test_options
      options.insecure.should be_false
      client = Deadfinder::HttpClient.create(uri, options)
      client.should be_a(HTTP::Client)
    end
  end

  describe ".proxy_configured?" do
    it "returns false when proxy is empty" do
      options = default_test_options
      options.proxy = ""
      Deadfinder::HttpClient.proxy_configured?(options).should be_false
    end

    it "returns true when proxy is set" do
      options = default_test_options
      options.proxy = "http://proxy.example.com:8080"
      Deadfinder::HttpClient.proxy_configured?(options).should be_true
    end
  end

  describe ".absolute_uri" do
    it "returns the full URI string" do
      uri = URI.parse("http://example.com/path?q=1")
      Deadfinder::HttpClient.absolute_uri(uri).should eq("http://example.com/path?q=1")
    end
  end

  describe ".request_path" do
    it "defaults an empty path to /" do
      Deadfinder::HttpClient.request_path(URI.parse("http://example.com"), default_test_options).should eq("/")
    end

    it "keeps the query string" do
      Deadfinder::HttpClient.request_path(URI.parse("http://example.com/a?b=1"), default_test_options)
        .should eq("/a?b=1")
    end

    it "uses an absolute URI when a proxy is configured for plain http" do
      options = default_test_options
      options.proxy = "http://127.0.0.1:8080"
      Deadfinder::HttpClient.request_path(URI.parse("http://example.com/a"), options)
        .should eq("http://example.com/a")
    end

    it "keeps origin-form for https even behind a proxy (CONNECT tunnel)" do
      options = default_test_options
      options.proxy = "http://127.0.0.1:8080"
      Deadfinder::HttpClient.request_path(URI.parse("https://example.com/a"), options).should eq("/a")
    end
  end

  describe ".build_headers" do
    it "parses headers and applies the default user agent" do
      headers = Deadfinder::HttpClient.build_headers(["X-Test: 1"], "UA/1")
      headers["X-Test"].should eq("1")
      headers["User-Agent"].should eq("UA/1")
    end

    it "lets an explicit User-Agent header win" do
      headers = Deadfinder::HttpClient.build_headers(["User-Agent: Custom"], "UA/1")
      headers["User-Agent"].should eq("Custom")
    end
  end

  describe ".decompress_if_gzip" do
    it "inflates a gzip body" do
      io = IO::Memory.new
      Compress::Gzip::Writer.open(io) { |gz| gz.print "<urlset/>" }
      Deadfinder::HttpClient.decompress_if_gzip(String.new(io.to_slice)).should eq("<urlset/>")
    end

    it "returns non-gzip bodies untouched" do
      Deadfinder::HttpClient.decompress_if_gzip("<urlset/>").should eq("<urlset/>")
    end

    it "returns the body untouched when the gzip stream is corrupt" do
      corrupt = String.new(Bytes[0x1f, 0x8b, 0x08, 0x00, 0x99, 0x99])
      Deadfinder::HttpClient.decompress_if_gzip(corrupt).should eq(corrupt)
    end
  end

  describe ".fetch" do
    before_each { WebMock.reset }

    it "returns the redirect response untouched when max_redirects is 0" do
      WebMock.stub(:get, "http://fetch.test/a")
        .to_return(status: 302, headers: {"Location" => "http://fetch.test/b"})

      response, final = Deadfinder::HttpClient.fetch(
        URI.parse("http://fetch.test/a"), default_test_options, HTTP::Headers.new)

      response.status_code.should eq(302)
      final.to_s.should eq("http://fetch.test/a")
    end

    it "follows redirects and reports the final URI" do
      WebMock.stub(:get, "http://fetch.test/a")
        .to_return(status: 301, headers: {"Location" => "/b"})
      WebMock.stub(:get, "http://fetch.test/b").to_return(status: 200, body: "done")

      response, final = Deadfinder::HttpClient.fetch(
        URI.parse("http://fetch.test/a"), default_test_options, HTTP::Headers.new, 5)

      response.status_code.should eq(200)
      response.body.should eq("done")
      final.to_s.should eq("http://fetch.test/b")
    end

    it "stops at the hop limit instead of following forever" do
      hops = 0
      WebMock.stub(:get, /^http:\/\/hops\.test\//).to_return do |request|
        hops += 1
        HTTP::Client::Response.new(302, body: "", headers: HTTP::Headers{"Location" => "/#{hops}"})
      end

      response, _ = Deadfinder::HttpClient.fetch(
        URI.parse("http://hops.test/"), default_test_options, HTTP::Headers.new, 3)

      response.status_code.should eq(302)
      hops.should eq(4) # initial request + 3 followed hops
    end

    it "stops on a redirect loop" do
      requests = 0
      WebMock.stub(:get, "http://loop.test/a").to_return do
        requests += 1
        HTTP::Client::Response.new(302, body: "", headers: HTTP::Headers{"Location" => "http://loop.test/b"})
      end
      WebMock.stub(:get, "http://loop.test/b").to_return do
        requests += 1
        HTTP::Client::Response.new(302, body: "", headers: HTTP::Headers{"Location" => "http://loop.test/a"})
      end

      Deadfinder::HttpClient.fetch(
        URI.parse("http://loop.test/a"), default_test_options, HTTP::Headers.new, 5)

      requests.should eq(2)
    end

    it "does not follow a redirect to a non-http scheme" do
      WebMock.stub(:get, "http://scheme.test/a")
        .to_return(status: 302, headers: {"Location" => "ftp://scheme.test/file"})

      response, final = Deadfinder::HttpClient.fetch(
        URI.parse("http://scheme.test/a"), default_test_options, HTTP::Headers.new, 5)

      response.status_code.should eq(302)
      final.to_s.should eq("http://scheme.test/a")
    end

    it "keeps credentials on a same-origin redirect" do
      seen : String? = nil
      WebMock.stub(:get, "http://same.test/a")
        .to_return(status: 302, headers: {"Location" => "http://same.test/b"})
      WebMock.stub(:get, "http://same.test/b").to_return do |request|
        seen = request.headers["Authorization"]?
        HTTP::Client::Response.new(200, body: "")
      end

      Deadfinder::HttpClient.fetch(URI.parse("http://same.test/a"), default_test_options,
        HTTP::Headers{"Authorization" => "Bearer secret"}, 5)

      seen.should eq("Bearer secret")
    end

    it "drops credentials when the redirect crosses origins" do
      seen : String? = "unset"
      WebMock.stub(:get, "http://origin.test/a")
        .to_return(status: 302, headers: {"Location" => "http://other.test/b"})
      WebMock.stub(:get, "http://other.test/b").to_return do |request|
        seen = request.headers["Authorization"]?
        HTTP::Client::Response.new(200, body: "")
      end

      headers = HTTP::Headers{"Authorization" => "Bearer secret", "X-Trace" => "keep"}
      Deadfinder::HttpClient.fetch(URI.parse("http://origin.test/a"), default_test_options, headers, 5)

      seen.should be_nil
      # The caller's headers must not be mutated by the strip.
      headers["Authorization"].should eq("Bearer secret")
    end

    it "keeps non-sensitive headers across an origin change" do
      seen : String? = nil
      WebMock.stub(:get, "http://origin2.test/a")
        .to_return(status: 302, headers: {"Location" => "http://other2.test/b"})
      WebMock.stub(:get, "http://other2.test/b").to_return do |request|
        seen = request.headers["X-Trace"]?
        HTTP::Client::Response.new(200, body: "")
      end

      Deadfinder::HttpClient.fetch(URI.parse("http://origin2.test/a"), default_test_options,
        HTTP::Headers{"Authorization" => "Bearer secret", "X-Trace" => "keep"}, 5)

      seen.should eq("keep")
    end
  end
end
