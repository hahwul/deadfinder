# DeadFinder (Crystal)

Crystal implementation of DeadFinder - a fast dead link finder. This is a high-performance port of the [Ruby version](https://github.com/hahwul/deadfinder) with native compilation and fiber-based concurrency.

## Installation

### From source

```bash
cd crystal
shards install
crystal build src/cli_main.cr -o deadfinder --release
```

### Requirements

- Crystal >= 1.19.1
- cmake (for building lexbor dependency)

## Usage

```bash
# Scan a single URL
deadfinder url https://example.com

# Scan URLs from a file
deadfinder file urls.txt

# Scan URLs from STDIN
cat urls.txt | deadfinder pipe

# Scan URLs from a sitemap
deadfinder sitemap https://example.com/sitemap.xml
```

### Options

```
-r, --include30x                 Include 30x redirections as dead links
-c, --concurrency=N              Number of concurrent workers (default: 50)
-t, --timeout=N                  Timeout in seconds (default: 10)
-o, --output=FILE                File to write results
-f, --output_format=FORMAT       Output format: json, yaml, toml, csv (default: json)
-H, --headers=HEADER             Custom HTTP headers for initial request
    --worker_headers=HEADER      Custom HTTP headers for worker requests
    --user_agent=UA              User-Agent string
-p, --proxy=PROXY                Proxy server (supports HTTP and HTTPS CONNECT)
    --proxy_auth=USER:PASS       Proxy authentication
-m, --match=PATTERN              Match URL pattern (regex)
-i, --ignore=PATTERN             Ignore URL pattern (regex)
-s, --silent                     Silent mode
-v, --verbose                    Verbose mode
    --debug                      Debug mode
    --limit=N                    Limit number of URLs to scan
    --coverage                   Enable coverage tracking and reporting
    --visualize=PATH             Generate visualization PNG
```

### Shell Completion

```bash
# Bash
deadfinder completion bash > /etc/bash_completion.d/deadfinder

# Zsh
deadfinder completion zsh > ~/.zsh/completion/_deadfinder

# Fish
deadfinder completion fish > ~/.config/fish/completions/deadfinder.fish
```

## Development

```bash
# Install dependencies
shards install

# Run tests
crystal spec

# Build (debug)
crystal build src/cli_main.cr -o deadfinder

# Build (release)
crystal build src/cli_main.cr -o deadfinder --release
```

## Contributing

1. Fork it (<https://github.com/hahwul/deadfinder/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [hahwul](https://github.com/hahwul) - creator and maintainer
