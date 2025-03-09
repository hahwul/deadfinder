require 'spec_helper'
require 'deadfinder/const'

RSpec.describe DeadFinder do
  it 'has a version number' do
    expect(DeadFinder::VERSION).not_to be nil
  end
end
