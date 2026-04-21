module Deadfinder
  module UrlPatternMatcher
    TIMEOUT_DURATION = 1.second

    def self.match?(url : String, pattern : String) : Bool
      matches_with_timeout?(url, pattern)
    end

    def self.ignore?(url : String, pattern : String) : Bool
      matches_with_timeout?(url, pattern)
    end

    private def self.matches_with_timeout?(url : String, pattern : String) : Bool
      regex = Regex.new(pattern)
      result_ch = Channel(Bool).new(1)
      spawn do
        result_ch.send(regex.matches?(url))
      end
      select
      when result = result_ch.receive
        result
      when timeout(TIMEOUT_DURATION)
        false
      end
    end
  end
end
