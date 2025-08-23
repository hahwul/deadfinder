# frozen_string_literal: true

require 'deadfinder'

# Example demonstrating coverage reporting functionality
puts "DeadFinder Coverage Report Example"
puts "==================================="

runner = DeadFinder::Runner.new
options = runner.default_options
options['concurrency'] = 30
options['output'] = 'examples/coverage_report_output.json'
options['output_format'] = 'json'

# Clear any existing data for clean demo
DeadFinder.output.clear
DeadFinder.coverage_data.clear

# This would normally be called with actual URLs that get tested
# For this example, we'll simulate the coverage tracking
puts "Simulating URL testing with coverage tracking..."

target = 'https://example.com'

# Simulate testing 10 URLs where 3 are dead
DeadFinder.coverage_data[target] = { total: 10, dead: 3 }
DeadFinder.output[target] = [
  'https://example.com/broken-link-1',
  'https://example.com/broken-link-2', 
  'https://example.com/broken-link-3'
]

# Generate output with coverage information
DeadFinder.gen_output(options)

puts "\nCoverage information has been included in the output file."
puts "Contents of #{options['output']}:"
puts "-" * 50

output_content = File.read(options['output'])
puts output_content

# Parse and display coverage summary
parsed = JSON.parse(output_content)
if parsed['coverage']
  summary = parsed['coverage']['summary']
  puts "\nCoverage Summary:"
  puts "- Total URLs tested: #{summary['total_tested']}"
  puts "- Dead links found: #{summary['total_dead']}"
  puts "- Coverage percentage: #{summary['overall_coverage_percentage']}%"
else
  puts "\nNo coverage data available (backward compatibility mode)"
end