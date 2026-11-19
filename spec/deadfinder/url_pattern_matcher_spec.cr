require "../spec_helper"

describe Deadfinder::UrlPatternMatcher do
  describe ".validate!" do
    it "accepts a valid pattern" do
      Deadfinder::UrlPatternMatcher.validate!("example\\.com/docs")
    end

    it "rejects an invalid regex" do
      expect_raises(ArgumentError) { Deadfinder::UrlPatternMatcher.validate!("[") }
    end

    it "rejects a catastrophic-backtracking pattern" do
      expect_raises(Deadfinder::UrlPatternMatcher::UnsafePatternError) do
        Deadfinder::UrlPatternMatcher.validate!("(a+)+")
      end
    end
  end

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

    it "does not match a URL that drives the pattern into PCRE2's match limit" do
      # `(\w|\d)+$` passes `validate!` and then gives up on a long digit run.
      # Raising aborted the caller's loop over the page, so the one URL is
      # answered instead — not matched keeps it out of the scan — and the
      # pattern goes on answering for the next URL.
      pattern = "/private/(\\w|\\d)+$"
      Deadfinder::UrlPatternMatcher.validate!(pattern)
      Deadfinder::UrlPatternMatcher.match?("/private/#{"1234567890" * 4}.x", pattern).should be_false
      Deadfinder::UrlPatternMatcher.match?("/private/logout", pattern).should be_true
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

    it "ignores a URL that drives the pattern into PCRE2's match limit" do
      # The mirror of `match?`: here "ignored" is the answer that keeps the URL
      # out of the scan.
      pattern = "/private/(\\w|\\d)+$"
      Deadfinder::UrlPatternMatcher.ignore?("/private/#{"1234567890" * 4}.x", pattern).should be_true
      Deadfinder::UrlPatternMatcher.ignore?("/public/ok", pattern).should be_false
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

    it "rejects brace-quantifier nested shapes like (\\w{2,5})+" do
      expect_raises(Deadfinder::UrlPatternMatcher::UnsafePatternError) do
        Deadfinder::UrlPatternMatcher.match?("aaaaaa", "(\\w{2,5})+")
      end
    end

    it "does not flag a bounded fixed-count group like (ab){2,5}" do
      # (ab){2,5} repeats a fixed-length group a bounded number of times — not
      # catastrophic, so it must still compile and match.
      Deadfinder::UrlPatternMatcher.match?("abab", "(ab){2,5}").should be_true
    end

    it "hands a match-time backtracking blowup to the block instead of raising" do
      # (a|a)* bypasses the static guard but PCRE2 raises a match-limit error at
      # match time. Raising it aborted the runner's filter loop mid-page, so the
      # caller is told why — to report it once per target — and still gets an
      # answer for this URL.
      reasons = [] of String
      Deadfinder::UrlPatternMatcher.match?("a" * 80 + "!", "(a|a)*$") { |reason| reasons << reason }.should be_false
      Deadfinder::UrlPatternMatcher.ignore?("a" * 80 + "!", "(a|a)*$") { |reason| reasons << reason }.should be_true
      Deadfinder::UrlPatternMatcher.match?("aaa", "(a|a)*$") { |reason| reasons << reason }.should be_true
      reasons.size.should eq 2
      reasons.first.should contain "(a|a)*$"
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
