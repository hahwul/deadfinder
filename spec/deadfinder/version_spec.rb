# frozen_string_literal: true

require 'uri'
require_relative '../../lib/deadfinder/version'

RSpec.describe 'Version' do
  describe 'VERSION' do
    it 'returns the correct version' do
      expect(VERSION).nil?
    end
  end
end
