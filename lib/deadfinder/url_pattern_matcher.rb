# frozen_string_literal: true

module DeadFinder
  # URL pattern matcher module
  module UrlPatternMatcher
    def self.match?(url, pattern)
      Regexp.new(pattern).match?(url)
    end

    def self.ignore?(url, pattern)
      Regexp.new(pattern).match?(url)
    end
  end
end
