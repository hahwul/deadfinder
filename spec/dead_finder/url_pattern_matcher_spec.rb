# frozen_string_literal: true

require 'deadfinder/url_pattern_matcher'

RSpec.describe DeadFinder::UrlPatternMatcher do
  describe '.match?' do
    it 'returns true when the URL matches the pattern' do
      expect(described_class.match?('http://example.com', 'example')).to be true
    end

    it 'returns false when the URL does not match the pattern' do
      expect(described_class.match?('http://example.com', 'nonexistent')).to be false
    end

    it 'raises an error when the pattern is an invalid regex' do
      expect { described_class.match?('http://example.com', '[') }.to raise_error(RegexpError)
    end

    it 'returns false when Timeout::Error is raised' do
      allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)
      expect(described_class.match?('http://example.com', 'example')).to be false
    end
  end

  describe '.ignore?' do
    it 'returns true when the URL matches the pattern' do
      expect(described_class.ignore?('http://example.com', 'example')).to be true
    end

    it 'returns false when the URL does not match the pattern' do
      expect(described_class.ignore?('http://example.com', 'nonexistent')).to be false
    end

    it 'raises an error when the pattern is an invalid regex' do
      expect { described_class.ignore?('http://example.com', '[') }.to raise_error(RegexpError)
    end

    it 'returns false when Timeout::Error is raised' do
      allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)
      expect(described_class.ignore?('http://example.com', 'example')).to be false
    end
  end
end
