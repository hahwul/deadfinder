require "../spec_helper"

describe Deadfinder::UrlPatternMatcher do
  describe ".match?" do
    it "returns true when the URL matches the pattern" do
      Deadfinder::UrlPatternMatcher.match?("http://example.com", "example").should be_true
    end

    it "returns false when the URL does not match the pattern" do
      Deadfinder::UrlPatternMatcher.match?("http://example.com", "nonexistent").should be_false
    end

    it "raises an error when the pattern is an invalid regex" do
      expect_raises(ArgumentError) do
        Deadfinder::UrlPatternMatcher.match?("http://example.com", "[")
      end
    end

    it "supports complex regex patterns" do
      Deadfinder::UrlPatternMatcher.match?("http://example.com/path/to/page", "path/to/\\w+").should be_true
    end

    it "supports anchored patterns" do
      Deadfinder::UrlPatternMatcher.match?("http://example.com", "^http://example").should be_true
      Deadfinder::UrlPatternMatcher.match?("http://example.com", "^https://example").should be_false
    end

    it "matches query parameters" do
      Deadfinder::UrlPatternMatcher.match?("http://example.com?foo=bar", "foo=bar").should be_true
    end
  end

  describe ".ignore?" do
    it "returns true when the URL matches the pattern" do
      Deadfinder::UrlPatternMatcher.ignore?("http://example.com", "example").should be_true
    end

    it "returns false when the URL does not match the pattern" do
      Deadfinder::UrlPatternMatcher.ignore?("http://example.com", "nonexistent").should be_false
    end

    it "raises an error when the pattern is an invalid regex" do
      expect_raises(ArgumentError) do
        Deadfinder::UrlPatternMatcher.ignore?("http://example.com", "[")
      end
    end

    it "can ignore multiple URL patterns with alternation" do
      Deadfinder::UrlPatternMatcher.ignore?("http://example.com/ads", "ads|tracking").should be_true
      Deadfinder::UrlPatternMatcher.ignore?("http://example.com/tracking", "ads|tracking").should be_true
      Deadfinder::UrlPatternMatcher.ignore?("http://example.com/page", "ads|tracking").should be_false
    end
  end
end
