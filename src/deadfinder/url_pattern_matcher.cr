module Deadfinder
  module UrlPatternMatcher
    MAX_PATTERN_LENGTH = 1024

    # Inherits from ArgumentError so existing `rescue ArgumentError`
    # sites in the runner continue to catch bad patterns uniformly.
    class UnsafePatternError < ArgumentError
    end

    @@regex_cache = {} of String => Regex
    @@regex_cache_mutex = Mutex.new

    # `--match` and `--ignore` ask the same question and differ only when it has
    # no answer: a pattern that got past `validate!` and drives PCRE2 into its
    # match limit on this one URL. Each then gives the answer that keeps the URL
    # out of the scan — not matched, or ignored — instead of raising, which
    # aborted the caller's loop and left every later link on the page
    # unfiltered. The block is handed the reason, so the caller can report it
    # once per target rather than once per URL.
    def self.match?(url : String, pattern : String, &) : Bool
      matches?(url, pattern) { |reason| yield reason; false }
    end

    def self.ignore?(url : String, pattern : String, &) : Bool
      matches?(url, pattern) { |reason| yield reason; true }
    end

    def self.match?(url : String, pattern : String) : Bool
      match?(url, pattern) { }
    end

    def self.ignore?(url : String, pattern : String) : Bool
      ignore?(url, pattern) { }
    end

    # Yields the reason when PCRE2 gives up on `url`; the block's value is then
    # the answer.
    private def self.matches?(url : String, pattern : String, & : String -> Bool) : Bool
      regex = compile(pattern)
      begin
        regex.matches?(url)
      rescue ex : Regex::Error
        # PCRE2 enforces an internal match limit and raises Regex::Error when a
        # guard-bypassing pattern backtracks catastrophically at match time.
        yield "Pattern caused excessive backtracking while matching: #{pattern.inspect} (#{ex.message})"
      end
    end

    # Raises ArgumentError when `pattern` does not compile or fails the static
    # ReDoS check. The CLI calls this before scanning: once the scan starts a
    # bad pattern only logs an error per target and the filter is skipped, so
    # `--match` would silently widen the scan to every link instead of
    # narrowing it.
    def self.validate!(pattern : String) : Nil
      compile(pattern)
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

    # Conservative static check for the classic nested-quantifier ReDoS shapes:
    #   (a+)+ , (a*)* , (.+){2,} , (\w{2,5})+ , (a{1,}){2,} , etc.
    # An inner quantifier here is `+`, `*`, or a *variable* brace repetition
    # `{n,}`/`{n,m}` (which has a comma) — a fixed `{n}` count is bounded and
    # not catastrophic, so it is intentionally not flagged.
    #
    # This static check cannot enumerate every catastrophic shape (e.g.
    # alternation overlap like `(a|a)*`); those are caught at match time by the
    # `rescue Regex::Error` backstop in `matches?` above.
    #
    # The `(?<!\\)` lookbehinds skip escaped literal parens so patterns
    # like `\(a+\)+` (literal `(`, one-or-more a, literal `)`, one-or-more)
    # are not flagged — they have no real nested group.
    private def self.reject_catastrophic_backtracking!(pattern : String) : Nil
      # A variable quantifier (`+`, `*`, or `{n,}`) immediately following a
      # closing group whose body itself contains a variable quantifier — e.g.
      # `(a+)+`, `(a*)*`, `(a+){2,}`, `(\w{2,5})+`.
      if pattern.matches?(/(?<!\\)\([^()]*(?:[+*]|\{\d*,\d*\})[^()]*(?<!\\)\)[+*]/) ||
         pattern.matches?(/(?<!\\)\([^()]*(?:[+*]|\{\d*,\d*\})[^()]*(?<!\\)\)\{\d*,\d*\}/)
        raise UnsafePatternError.new("Pattern has nested quantifiers that can cause catastrophic backtracking: #{pattern.inspect}")
      end
    end
  end
end
