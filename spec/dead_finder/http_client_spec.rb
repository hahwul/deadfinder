# frozen_string_literal: true

require 'deadfinder/http_client'
require 'net/http'

RSpec.describe DeadFinder::HttpClient do
  describe '.create' do
    let(:uri) { URI.parse('http://example.com') }
    let(:https_uri) { URI.parse('https://example.com') }

    context 'without proxy' do
      it 'creates an HTTP client' do
        options = {}
        http = described_class.create(uri, options)
        expect(http).to be_a(Net::HTTP)
        expect(http).not_to be_use_ssl
      end

      it 'creates an HTTPS client' do
        options = {}
        http = described_class.create(https_uri, options)
        expect(http).to be_a(Net::HTTP)
        expect(http).to be_use_ssl
      end
    end

    context 'with proxy' do
      let(:proxy_uri) { 'http://proxy.example.com:8080' }

      it 'creates an HTTP client with proxy' do
        options = { 'proxy' => proxy_uri }
        http = described_class.create(uri, options)
        expect(http).to be_a(Net::HTTP)
        expect(http.proxy_address).to eq('proxy.example.com')
        expect(http.proxy_port).to eq(8080)
      end

      it 'creates an HTTPS client with proxy' do
        options = { 'proxy' => proxy_uri }
        http = described_class.create(https_uri, options)
        expect(http).to be_a(Net::HTTP)
        expect(http.proxy_address).to eq('proxy.example.com')
        expect(http.proxy_port).to eq(8080)
        expect(http).to be_use_ssl
      end
    end

    context 'with timeout' do
      it 'sets the read timeout' do
        options = { 'timeout' => '10' }
        http = described_class.create(uri, options)
        expect(http.read_timeout).to eq(10)
      end
    end

    context 'with proxy authentication' do
      let(:proxy_uri) { 'http://proxy.example.com:8080' }
      let(:proxy_auth) { 'user:password' }

      it 'sets the proxy user and password' do
        options = { 'proxy' => proxy_uri, 'proxy_auth' => proxy_auth }
        http = described_class.create(uri, options)
        expect(http.proxy_user).to eq('user')
        expect(http.proxy_pass).to eq('password')
      end
    end
  end
end
