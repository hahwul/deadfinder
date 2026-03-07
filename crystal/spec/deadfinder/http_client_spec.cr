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

    it "falls back to direct connection when proxy has no host" do
      uri = URI.parse("http://example.com")
      options = default_test_options
      options.proxy = "not-a-valid-proxy"
      client = Deadfinder::HttpClient.create(uri, options)
      client.should be_a(HTTP::Client)
    end

    it "creates client without proxy when proxy is empty" do
      uri = URI.parse("http://example.com")
      options = default_test_options
      options.proxy = ""
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
end
