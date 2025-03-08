# frozen_string_literal: true

require 'webmock/rspec'
require 'simplecov'
require 'simplecov-cobertura'
# Coverage
SimpleCov.start
SimpleCov.formatter = SimpleCov::Formatter::CoberturaFormatter

# Mock
WebMock.disable_net_connect!(allow_localhost: true)
