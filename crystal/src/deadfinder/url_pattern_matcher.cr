module Deadfinder
  module UrlPatternMatcher
    def self.match?(url : String, pattern : String) : Bool
      Regex.new(pattern).matches?(url)
    end

    def self.ignore?(url : String, pattern : String) : Bool
      Regex.new(pattern).matches?(url)
    end
  end
end
