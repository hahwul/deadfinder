module Deadfinder
  module UrlPatternMatcher
    MAX_PATTERN_LENGTH = 1024

    # Inherits from ArgumentError so existing `rescue ArgumentError`
    # sites in the runner continue to catch bad patterns uniformly.
    class UnsafePatternError < ArgumentError
    end

    @@regex_cache = {} of String => Regex
    @@regex_cache_mutex = Mutex.new

    def self.match?(url : String, pattern : String) : Bool
      regex = compile(pattern)
      regex.matches?(url)
    end

    def self.ignore?(url : String, pattern : String) : Bool
      regex = compile(pattern)
      regex.matches?(url)
    end

    # Exposed for tests / diagnostics.
    def self.clear_cache : Nil
      @@regex_cache_mutex.synchronize { @@regex_cache.clear }
    end

    private def self.compile(pattern : String) : Regex
      if pattern.size > MAX_PATTERN_LENGTH
        raise UnsafePatternError.new("Pattern exceeds #{MAX_PATTERN_LENGTH} characters (got #{pattern.size})")
      end
      reject_catastrophic_backtracking!(pattern)

      @@regex_cache_mutex.synchronize do
        @@regex_cache[pattern] ||= Regex.new(pattern)
      end
    end

    # Conservative static check for the two classic ReDoS shapes:
    #   (a+)+ , (a*)* , (a|a)* , (.+)* , etc.
    # Crystal's stdlib exposes no PCRE2 match-limit, and a fiber `timeout`
    # cannot interrupt a CPU-bound regex (fibers are cooperative), so we
    # reject the pattern up-front instead of pretending a timeout protects us.
    #
    # The `(?<!\\)` lookbehinds skip escaped literal parens so patterns
    # like `\(a+\)+` (literal `(`, one-or-more a, literal `)`, one-or-more)
    # are not flagged — they have no real nested group.
    private def self.reject_catastrophic_backtracking!(pattern : String) : Nil
      # Any quantifier (`+`, `*`, or `{n,}`) immediately following a closing
      # group that itself contains a quantifier — e.g. `(a+)+`, `(a*)*`,
      # `(a+){2,}`. Non-capturing groups and alternations match the same way.
      if pattern.matches?(/(?<!\\)\([^()]*[+*][^()]*(?<!\\)\)[+*]/) ||
         pattern.matches?(/(?<!\\)\([^()]*[+*][^()]*(?<!\\)\)\{\d*,\d*\}/)
        raise UnsafePatternError.new("Pattern has nested quantifiers that can cause catastrophic backtracking: #{pattern.inspect}")
      end
    end
  end
end
