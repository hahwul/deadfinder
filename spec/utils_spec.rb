# frozen_string_literal: true

require 'uri'
require_relative '../lib/deadfinder/utils'

RSpec.describe 'Utils' do
  describe '#generate_url' do
    let(:base_url) { 'http://example.com/base/' }

    it 'returns the original URL if it starts with http://' do
      expect(generate_url('http://example.com', base_url)).to eq('http://example.com')
    end

    it 'returns the original URL if it starts with https://' do
      expect(generate_url('https://example.com', base_url)).to eq('https://example.com')
    end

    it 'prepends the scheme if the URL starts with //' do
      expect(generate_url('//example.com', base_url)).to eq('http://example.com')
    end

    it 'prepends the scheme and host if the URL starts with /' do
      expect(generate_url('/path', base_url)).to eq('http://example.com/path')
    end

    it 'returns nil if the URL should ignore the scheme' do
      expect(generate_url('mailto:test@example.com', base_url)).to be_nil
    end

    it 'prepends the base directory if the URL is relative' do
      expect(generate_url('relative/path', base_url)).to eq('http://example.com/base/relative/path')
    end
  end

  describe '#ignore_scheme?' do
    it 'returns true for mailto: URLs' do
      expect(ignore_scheme?('mailto:test@example.com')).to be true
    end

    it 'returns true for tel: URLs' do
      expect(ignore_scheme?('tel:1234567890')).to be true
    end

    it 'returns true for sms: URLs' do
      expect(ignore_scheme?('sms:1234567890')).to be true
    end

    it 'returns true for data: URLs' do
      expect(ignore_scheme?('data:text/plain;base64,SGVsbG8sIFdvcmxkIQ==')).to be true
    end

    it 'returns true for file: URLs' do
      expect(ignore_scheme?('file:///path/to/file')).to be true
    end

    it 'returns false for other URLs' do
      expect(ignore_scheme?('http://example.com')).to be false
    end
  end

  describe '#extract_directory' do
    it 'returns the base URL if the path ends with /' do
      uri = URI('http://example.com/base/')
      expect(extract_directory(uri)).to eq('http://example.com/base/')
    end

    it 'returns the directory path if the path does not end with /' do
      uri = URI('http://example.com/base/file')
      expect(extract_directory(uri)).to eq('http://example.com/base/')
    end
  end
end
