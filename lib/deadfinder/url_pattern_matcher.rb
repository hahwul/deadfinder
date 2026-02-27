# frozen_string_literal: true

require 'timeout'

module DeadFinder
  # URL pattern matcher module
  module UrlPatternMatcher
    TIMEOUT_DURATION = 1

    def self.match?(url, pattern)
      Timeout.timeout(TIMEOUT_DURATION) { Regexp.new(pattern).match?(url) }
    rescue Timeout::Error
      false
    end

    def self.ignore?(url, pattern)
      Timeout.timeout(TIMEOUT_DURATION) { Regexp.new(pattern).match?(url) }
    rescue Timeout::Error
      false
    end
  end
end
