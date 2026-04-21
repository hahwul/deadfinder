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

  describe "ReDoS guardrails" do
    before_each { Deadfinder::UrlPatternMatcher.clear_cache }

    it "rejects patterns longer than MAX_PATTERN_LENGTH" do
      long_pattern = "a" * (Deadfinder::UrlPatternMatcher::MAX_PATTERN_LENGTH + 1)
      expect_raises(Deadfinder::UrlPatternMatcher::UnsafePatternError) do
        Deadfinder::UrlPatternMatcher.match?("http://example.com", long_pattern)
      end
    end

    it "rejects classic nested-quantifier ReDoS shapes like (a+)+" do
      expect_raises(Deadfinder::UrlPatternMatcher::UnsafePatternError) do
        Deadfinder::UrlPatternMatcher.match?("aaaa", "(a+)+")
      end
    end

    it "rejects (a*)* " do
      expect_raises(Deadfinder::UrlPatternMatcher::UnsafePatternError) do
        Deadfinder::UrlPatternMatcher.ignore?("aaaa", "(a*)*")
      end
    end

    it "rejects (.+){2,} bounded-repeat variant" do
      expect_raises(Deadfinder::UrlPatternMatcher::UnsafePatternError) do
        Deadfinder::UrlPatternMatcher.match?("aaaa", "(.+){2,}")
      end
    end

    it "UnsafePatternError is-a ArgumentError so runner rescue still catches" do
      (Deadfinder::UrlPatternMatcher::UnsafePatternError < ArgumentError).should be_true
    end

    it "does not flag patterns with escaped literal parens" do
      # `\(a+\)+` = literal `(`, one-or-more `a`, literal `)`, one-or-more —
      # there's no actual group being quantified, so no catastrophic backtracking.
      Deadfinder::UrlPatternMatcher.match?("(aaa))))", "\\(a+\\)+").should be_true
    end
  end

  describe "regex caching" do
    before_each { Deadfinder::UrlPatternMatcher.clear_cache }

    it "reuses the compiled regex across calls with the same pattern" do
      pattern = "example"
      Deadfinder::UrlPatternMatcher.match?("http://example.com", pattern)
      Deadfinder::UrlPatternMatcher.match?("http://example.org", pattern)
      Deadfinder::UrlPatternMatcher.match?("http://other.com", pattern)
      # No public accessor to the cache map, but we at least exercise the
      # hot path to confirm it does not blow up and returns consistent results.
      Deadfinder::UrlPatternMatcher.match?("http://example.com", pattern).should be_true
    end
  end
end
