# frozen_string_literal: true

require 'deadfinder'
require 'rspec'

RSpec.describe 'DeadFinder.calculate_coverage status counts' do
  before do
    DeadFinder.coverage_data.clear
  end

  it 'aggregates status counts correctly from multiple targets' do
    # Target 1: total 10, dead 2 (200 OK: 8, 404 Not Found: 2)
    DeadFinder.coverage_data['http://example1.com'] = {
      total: 10,
      dead: 2,
      status_counts: { 200 => 8, 404 => 2 }
    }

    # Target 2: total 5, dead 1 (200 OK: 4, 'error': 1)
    DeadFinder.coverage_data['http://example2.com'] = {
      total: 5,
      dead: 1,
      status_counts: { 200 => 4, 'error' => 1 }
    }

    coverage = DeadFinder.calculate_coverage
    overall_status_counts = coverage[:summary][:overall_status_counts]

    expect(overall_status_counts[200]).to eq(12)    # 8 + 4
    expect(overall_status_counts[404]).to eq(2)     # 2 + 0
    expect(overall_status_counts['error']).to eq(1) # 0 + 1

    # Check total tested and dead for completeness
    expect(coverage[:summary][:total_tested]).to eq(15)
    expect(coverage[:summary][:total_dead]).to eq(3)
  end

  it 'handles missing status counts gracefully' do
    DeadFinder.coverage_data['http://example1.com'] = {
      total: 10,
      dead: 2,
      status_counts: { 200 => 8, 404 => 2 }
    }

    # Target 2 has no status counts (should be treated as empty)
    DeadFinder.coverage_data['http://example2.com'] = {
      total: 5,
      dead: 1,
      status_counts: {}
    }

    coverage = DeadFinder.calculate_coverage
    overall_status_counts = coverage[:summary][:overall_status_counts]

    expect(overall_status_counts[200]).to eq(8)
    expect(overall_status_counts[404]).to eq(2)
  end
end
