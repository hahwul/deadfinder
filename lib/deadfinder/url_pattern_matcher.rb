# frozen_string_literal: true

require 'timeout'

module DeadFinder
  # URL pattern matcher module
  module UrlPatternMatcher
    def self.match?(url, pattern)
      Timeout.timeout(1) { Regexp.new(pattern).match?(url) }
    rescue Timeout::Error
      false
    end

    def self.ignore?(url, pattern)
      Timeout.timeout(1) { Regexp.new(pattern).match?(url) }
    rescue Timeout::Error
      false
    end
  end
end
