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

    it 'returns nil if URI.join raises an exception (e.g. invalid characters)' do
      # 비 ASCII 문자가 들어가서 에러가 발생하는 경우 nil 리턴을 확인
      bad_url = "invalid\uC640-\uB3C4\uBA54\uC778"
      expect(generate_url(bad_url, base_url)).to be_nil
    end

    it 'returns nil if base_url is invalid' do
      # 잘못된 기준 URL을 전달했을 경우에도 예외 발생 후 nil 리턴
      expect(generate_url('relative/path', '://invalid')).to be_nil
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
end