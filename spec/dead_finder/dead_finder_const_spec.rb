# frozen_string_literal: true

require 'spec_helper'
require 'deadfinder/const'

RSpec.describe DeadFinder do
  it 'has a version number' do
    expect(DeadFinder::VERSION).not_to be_nil
  end
end
