---
title: "Ruby API"
weight: 2
---

DeadFinder can be used as a Ruby library in your applications. This page covers the Ruby API usage.

## Installation

Add DeadFinder to your Gemfile:

```ruby
gem 'deadfinder'
```

Then run:

```bash
bundle install
```

## Basic Usage

```ruby
require 'deadfinder'

# Create a new runner
runner = DeadFinder::Runner.new
options = runner.default_options

# Configure options
options['concurrency'] = 30
options['timeout'] = 15

# Scan a single URL
DeadFinder.run_url('https://www.example.com', options)

# Get the results
puts DeadFinder.output
# => {"https://www.example.com" => ["https://www.example.com/broken-link"]}
```

## API Methods

### DeadFinder.run_url(url, options)

Scan a single URL for dead links.

**Parameters:**
- `url` (String): The URL to scan
- `options` (Hash): Configuration options

**Example:**

```ruby
require 'deadfinder'

runner = DeadFinder::Runner.new
options = runner.default_options
options['concurrency'] = 50
options['timeout'] = 10

DeadFinder.run_url('https://www.example.com', options)
results = DeadFinder.output
```

### DeadFinder.run_file(filename, options)

Scan URLs from a file (one URL per line).

**Parameters:**
- `filename` (String): Path to file containing URLs
- `options` (Hash): Configuration options

**Example:**

```ruby
require 'deadfinder'

runner = DeadFinder::Runner.new
options = runner.default_options
options['silent'] = true

DeadFinder.run_file('urls.txt', options)
results = DeadFinder.output
```

### DeadFinder.run_sitemap(sitemap_url, options)

Scan all URLs from a sitemap.

**Parameters:**
- `sitemap_url` (String): URL of the sitemap
- `options` (Hash): Configuration options

**Example:**

```ruby
require 'deadfinder'

runner = DeadFinder::Runner.new
options = runner.default_options
options['concurrency'] = 30

DeadFinder.run_sitemap('https://www.example.com/sitemap.xml', options)
results = DeadFinder.output
```

### DeadFinder.run_pipe(urls, options)

Scan URLs from an array (similar to pipe mode).

**Parameters:**
- `urls` (Array): Array of URLs to scan
- `options` (Hash): Configuration options

**Example:**

```ruby
require 'deadfinder'

runner = DeadFinder::Runner.new
options = runner.default_options

urls = [
  'https://www.example.com',
  'https://www.example.org'
]

DeadFinder.run_pipe(urls, options)
results = DeadFinder.output
```

### DeadFinder.output

Get the results of the last scan.

**Returns:** Hash containing the scan results

**Example:**

```ruby
results = DeadFinder.output
# => {
#   "https://www.example.com" => [
#     "https://www.example.com/broken-link1",
#     "https://www.example.com/broken-link2"
#   ]
# }
```

## Configuration Options

### Default Options

Get default options from the runner:

```ruby
runner = DeadFinder::Runner.new
options = runner.default_options
```

Default options include:

```ruby
{
  'concurrency' => 50,
  'timeout' => 10,
  'silent' => false,
  'verbose' => false,
  'debug' => false,
  'include30x' => false,
  'headers' => [],
  'worker_headers' => [],
  'user_agent' => 'Mozilla/5.0 (compatible; DeadFinder/1.9.1;)',
  'proxy' => nil,
  'proxy_auth' => nil,
  'match' => nil,
  'ignore' => nil,
  'coverage' => false,
  'visualize' => nil
}
```

### Customizing Options

You can customize any option:

```ruby
runner = DeadFinder::Runner.new
options = runner.default_options

# Performance options
options['concurrency'] = 30
options['timeout'] = 15

# Output options
options['silent'] = true
options['verbose'] = false

# HTTP options
options['include30x'] = true
options['headers'] = ['Authorization: Bearer token']
options['user_agent'] = 'MyBot/1.0'

# Filtering options
options['match'] = 'api|v1'
options['ignore'] = 'static|cdn'

# Analysis options
options['coverage'] = true
options['visualize'] = 'report.png'

DeadFinder.run_url('https://www.example.com', options)
```

## Advanced Examples

### Scanning Multiple URLs

```ruby
require 'deadfinder'

runner = DeadFinder::Runner.new
options = runner.default_options
options['silent'] = true

urls = [
  'https://www.example.com',
  'https://www.example.org',
  'https://www.example.net'
]

results = {}
urls.each do |url|
  DeadFinder.run_url(url, options)
  results[url] = DeadFinder.output
end

puts results.inspect
```

### Custom Result Processing

```ruby
require 'deadfinder'
require 'json'

runner = DeadFinder::Runner.new
options = runner.default_options
options['coverage'] = true

DeadFinder.run_url('https://www.example.com', options)
results = DeadFinder.output

# Process results
if results.empty?
  puts "No dead links found!"
else
  results.each do |origin, dead_links|
    puts "Found #{dead_links.count} dead links on #{origin}:"
    dead_links.each do |link|
      puts "  - #{link}"
    end
  end
end

# Save to file
File.write('results.json', JSON.pretty_generate(results))
```

### Integration with Rails

```ruby
# app/services/dead_link_checker.rb
class DeadLinkChecker
  def self.check(url)
    require 'deadfinder'
    
    runner = DeadFinder::Runner.new
    options = runner.default_options
    options['silent'] = true
    options['timeout'] = 30
    
    DeadFinder.run_url(url, options)
    DeadFinder.output
  end
  
  def self.check_multiple(urls)
    results = {}
    urls.each do |url|
      results[url] = check(url)
    end
    results
  end
end

# Usage in controller or background job
results = DeadLinkChecker.check('https://www.example.com')
```

### Background Job with Sidekiq

```ruby
# app/workers/dead_link_check_worker.rb
class DeadLinkCheckWorker
  include Sidekiq::Worker
  
  def perform(url)
    require 'deadfinder'
    
    runner = DeadFinder::Runner.new
    options = runner.default_options
    options['silent'] = true
    
    DeadFinder.run_url(url, options)
    results = DeadFinder.output
    
    if results.any? { |_, links| links.any? }
      # Notify about dead links
      DeadLinkMailer.notify(url, results).deliver_later
    end
  end
end

# Schedule the job
DeadLinkCheckWorker.perform_async('https://www.example.com')
```

### Rake Task

```ruby
# lib/tasks/dead_links.rake
namespace :dead_links do
  desc "Check for dead links in the application"
  task check: :environment do
    require 'deadfinder'
    
    runner = DeadFinder::Runner.new
    options = runner.default_options
    options['silent'] = false
    options['coverage'] = true
    
    # Check main pages
    urls = [
      "#{Rails.application.routes.url_helpers.root_url}",
      "#{Rails.application.routes.url_helpers.about_url}",
      "#{Rails.application.routes.url_helpers.contact_url}"
    ]
    
    all_results = {}
    urls.each do |url|
      puts "Checking #{url}..."
      DeadFinder.run_url(url, options)
      results = DeadFinder.output
      all_results.merge!(results) if results.any?
    end
    
    if all_results.empty?
      puts "✓ No dead links found!"
    else
      puts "✗ Dead links found:"
      all_results.each do |origin, dead_links|
        puts "\n#{origin}:"
        dead_links.each { |link| puts "  - #{link}" }
      end
      exit 1
    end
  end
end
```

### Testing with RSpec

```ruby
# spec/services/dead_link_checker_spec.rb
require 'rails_helper'

RSpec.describe DeadLinkChecker do
  describe '.check' do
    it 'returns dead links for a URL' do
      url = 'https://www.example.com'
      results = DeadLinkChecker.check(url)
      
      expect(results).to be_a(Hash)
    end
    
    it 'handles errors gracefully' do
      invalid_url = 'invalid-url'
      
      expect {
        DeadLinkChecker.check(invalid_url)
      }.not_to raise_error
    end
  end
end
```

## Error Handling

```ruby
require 'deadfinder'

begin
  runner = DeadFinder::Runner.new
  options = runner.default_options
  
  DeadFinder.run_url('https://www.example.com', options)
  results = DeadFinder.output
  
  if results.empty?
    puts "No dead links found"
  else
    puts "Found dead links: #{results.inspect}"
  end
rescue StandardError => e
  puts "Error occurred: #{e.message}"
  puts e.backtrace
end
```

## Logger Integration

DeadFinder uses its own logger, but you can integrate it with your application's logger:

```ruby
require 'deadfinder'

# The logger is used internally by DeadFinder
# You can capture the output by setting the silent option
runner = DeadFinder::Runner.new
options = runner.default_options
options['silent'] = true  # Suppress DeadFinder's own logging

DeadFinder.run_url('https://www.example.com', options)
results = DeadFinder.output

# Log to your own logger
Rails.logger.info "Dead link check completed: #{results.inspect}"
```

## API Reference

For complete API documentation, visit [RubyDoc](https://rubydoc.info/gems/deadfinder/DeadFinder).

For more examples, see the [examples directory](https://github.com/hahwul/deadfinder/tree/main/examples) in the repository.
