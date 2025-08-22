# DeadFinder - Dead Link Detection Tool

DeadFinder is a Ruby gem that finds broken links (dead links) in web pages. It provides a command-line interface, Ruby library API, and GitHub Action for detecting broken URLs in websites, sitemaps, and files.

Always reference these instructions first and fallback to search or bash commands only when you encounter unexpected information that does not match the info here.

## Working Effectively

### Prerequisites and Setup
- Install Ruby 3.2+ (officially requires 3.4+, but 3.2+ works):
  - Check version: `ruby --version`
- Install bundler for user if not available: `gem install bundler --user-install`
- Add bundler to PATH: `export PATH="$HOME/.local/share/gem/ruby/3.2.0/bin:$PATH"`

### Bootstrap and Dependencies  
- Set up the repository:
  - `chmod +x bin/setup && ./bin/setup`
  - OR manually: `bundle config set --local path 'vendor/bundle' && bundle install`
- NEVER CANCEL: Bundle install takes 2-3 minutes. Set timeout to 5+ minutes.

### Building and Testing
- Build: NOT APPLICABLE - This is a Ruby gem, no compilation required
- Run tests: `bundle exec rspec`
  - TIMING: Tests complete in ~0.12 seconds (85 tests). Set timeout to 1 minute for safety.
- Run linter: `bundle exec rubocop`  
  - TIMING: Linting takes ~5-10 seconds. Set timeout to 1 minute for safety.

### Running the Application
- CLI interface: `bundle exec ruby -I lib bin/deadfinder <command>`
- Available commands:
  - `bundle exec ruby -I lib bin/deadfinder --help` - Show help
  - `bundle exec ruby -I lib bin/deadfinder version` - Show version  
  - `bundle exec ruby -I lib bin/deadfinder url <URL>` - Scan single URL
  - `bundle exec ruby -I lib bin/deadfinder file <filename>` - Scan URLs from file
  - `bundle exec ruby -I lib bin/deadfinder sitemap <sitemap-url>` - Scan URLs from sitemap
  - `bundle exec ruby -I lib bin/deadfinder pipe` - Scan URLs from STDIN
  - `bundle exec ruby -I lib bin/deadfinder completion <shell>` - Generate shell completion

## Validation

### Manual Testing Scenarios
ALWAYS test functionality after making changes by running through these scenarios:

1. **Basic CLI functionality**:
   - `bundle exec ruby -I lib bin/deadfinder version` - Should show version info
   - `bundle exec ruby -I lib bin/deadfinder --help` - Should display help text

2. **URL scanning** (will show network errors in sandbox environment, but tool should work):
   - Create test file: `echo -e "https://example.com\nhttps://nonexistent.example" > /tmp/test_urls.txt`
   - `bundle exec ruby -I lib bin/deadfinder file /tmp/test_urls.txt --silent`
   - Should run without crashing (network errors are expected)

3. **Ruby API usage**:
   - `bundle exec ruby -I lib -e "require 'deadfinder'; puts DeadFinder::VERSION"`
   - Should print version number

### Build Validation
- ALWAYS run `bundle exec rspec` before committing changes
- ALWAYS run `bundle exec rubocop` before committing changes  
- Both must pass for CI to succeed

## Common Tasks

### Repository Structure
```
/home/runner/work/deadfinder/deadfinder/
├── bin/
│   ├── console          # IRB console with deadfinder loaded
│   ├── deadfinder       # Main CLI executable 
│   └── setup           # Setup script
├── lib/
│   ├── deadfinder.rb              # Main module
│   └── deadfinder/
│       ├── cli.rb                 # Thor-based CLI
│       ├── runner.rb              # Core scanning logic
│       ├── logger.rb              # Logging utilities
│       ├── utils.rb               # Utility functions
│       ├── version.rb             # Version constant
│       ├── http_client.rb         # HTTP client wrapper
│       ├── url_pattern_matcher.rb # URL pattern matching
│       └── completion.rb          # Shell completion
├── spec/                          # RSpec test suite
├── examples/                      # Usage examples
├── github-action/                 # GitHub Action implementation
├── Gemfile                        # Dependencies
├── deadfinder.gemspec            # Gem specification
├── Rakefile                      # Rake tasks
└── .rubocop.yml                  # Linting configuration
```

### Key Project Files
- **CLI Entry Point**: `bin/deadfinder` - Thor-based command line interface
- **Core Library**: `lib/deadfinder.rb` - Main module with scanning functions
- **Test Suite**: `spec/` - RSpec tests (85 tests, all passing)
- **Examples**: `examples/` - Ruby usage examples for different modes
- **GitHub Action**: `github-action/` - Docker-based GitHub Action

### CLI Usage Patterns
```shell
# Scan single URL
bundle exec ruby -I lib bin/deadfinder url https://example.com

# Scan multiple URLs from file  
bundle exec ruby -I lib bin/deadfinder file urls.txt

# Scan sitemap
bundle exec ruby -I lib bin/deadfinder sitemap https://example.com/sitemap.xml

# Scan from STDIN
cat urls.txt | bundle exec ruby -I lib bin/deadfinder pipe

# Output options
bundle exec ruby -I lib bin/deadfinder url https://example.com -o output.json -f json
bundle exec ruby -I lib bin/deadfinder url https://example.com -o output.yaml -f yaml
bundle exec ruby -I lib bin/deadfinder url https://example.com -o output.csv -f csv

# Advanced options
bundle exec ruby -I lib bin/deadfinder url https://example.com --concurrency=30 --timeout=15 --silent
```

### Ruby API Usage Patterns
```ruby
require 'deadfinder'

# Basic usage
runner = DeadFinder::Runner.new
options = runner.default_options
options['concurrency'] = 30

DeadFinder.run_url('https://example.com', options)
puts DeadFinder.output

# Multiple URLs
DeadFinder.run_file('urls.txt', options)
puts DeadFinder.output

# Sitemap scanning
DeadFinder.run_sitemap('https://example.com/sitemap.xml', options)
puts DeadFinder.output
```

### GitHub Action Usage
```yaml
steps:
- name: Run DeadFinder
  uses: hahwul/deadfinder@latest
  with:
    command: sitemap
    target: https://example.com/sitemap.xml
    timeout: 10
    concurrency: 50
```

### Development Workflow
1. Make changes to code
2. Run tests: `bundle exec rspec` (must pass)
3. Run linter: `bundle exec rubocop` (must pass) 
4. Test CLI manually with validation scenarios above
5. Commit changes

### Installation Methods
- **Gem**: `gem install deadfinder`
- **Homebrew**: `brew install deadfinder`  
- **Docker**: `docker pull ghcr.io/hahwul/deadfinder:latest`
- **Development**: `bundle config set --local path 'vendor/bundle' && bundle install`

### Output Formats
- **JSON** (default): `{"origin_url": ["broken_link1", "broken_link2"]}`
- **YAML**: YAML formatted output
- **CSV**: Comma-separated values with target,url columns

### Common Options
- `--concurrency=N` - Number of concurrent workers (default: 50)
- `--timeout=N` - Request timeout in seconds (default: 10)  
- `--silent` - Suppress output during scanning
- `--verbose` - Verbose output with detailed information
- `--output=FILE` - Write results to file
- `--output-format=FORMAT` - Output format (json, yaml, csv)
- `--headers="Header: Value"` - Custom HTTP headers
- `--match=PATTERN` - Only include URLs matching pattern
- `--ignore=PATTERN` - Ignore URLs matching pattern
- `--proxy=URL` - Use proxy server
- `--user-agent=STRING` - Custom User-Agent string

### Network Considerations
- Tool requires internet access for actual URL scanning
- In sandboxed environments, network requests may fail (this is expected)
- Tool functionality can still be validated even with network errors
- Use short timeouts (5-10 seconds) for testing to avoid hangs

### Error Handling
- Network errors are expected and handled gracefully
- Invalid URLs are logged but don't crash the application
- Missing files result in clear error messages
- Invalid regex patterns in --match/--ignore are logged as errors

### Performance Notes
- Default concurrency: 50 workers
- Default timeout: 10 seconds per request
- Large sitemaps may take time to process (this is normal)
- Memory usage scales with number of URLs being processed