<div align="center">
  <picture>
    <img alt="DeadFinder Logo" src="https://github.com/user-attachments/assets/1523d0be-31dd-4031-ac97-5feda474a6e9" width="500px;">
  </picture>
  <p>Find dead-links (broken links)</p>
</div>

<p align="center">
  <a href="#contributions-welcome"><img src="https://img.shields.io/badge/CONTRIBUTIONS-WELCOME-000000?style=for-the-badge&labelColor=000000"></a>
  <a href="https://app.codecov.io/gh/hahwul/deadfinder/"><img src="https://img.shields.io/codecov/c/gh/hahwul/deadfinder?style=for-the-badge&color=000000&logo=codecov&labelColor=000000"></a>
  <a href="https://rubygems.org/gems/deadfinder"><img src="https://img.shields.io/gem/v/deadfinder?style=for-the-badge&color=000000&logo=ruby&labelColor=000000&logoColor=red"></a>
  <a href="https://formulae.brew.sh/formula/deadfinder"><img src="https://img.shields.io/homebrew/v/deadfinder?style=for-the-badge&color=000000&logo=homebrew&labelColor=000000"></a>
</p>

Dead link (broken link) means a link within a web page that cannot be connected. These links can have a negative impact to SEO and Security. This tool makes it easy to identify and modify.

![](https://github.com/user-attachments/assets/92129de9-90c6-41e0-a424-883fe30858f6)

## Installation
### Install with Gem
#### CLI
```bash
gem install deadfinder
# https://rubygems.org/gems/deadfinder
```

#### Gemfile

```ruby
gem 'deadfinder'
# and `bundle install`
```

### Install with Homebrew
```bash
brew install deadfinder
# https://formulae.brew.sh/formula/deadfinder
```

### Docker Image
```shell
docker pull ghcr.io/hahwul/deadfinder:latest
```

## Using In
### CLI
```shell
deadfinder sitemap https://www.hahwul.com/sitemap.xml
```

### Github Action
```yml
steps:
- name: Run DeadFinder
  uses: hahwul/deadfinder@1.6.1
  # or uses: hahwul/deadfinder@latest
  id: broken-link
  with:
    command: sitemap # url / file / sitemap
    target: https://www.hahwul.com/sitemap.xml
    # timeout: 10
    # concurrency: 50
    # silent: false
    # headers: "X-API-Key: 123444"
    # worker_headers: "User-Agent: Deadfinder Bot"
    # include30x: false
    # user_agent: "Apple"
    # proxy: "http://localhost:8070"

- name: Output Handling
  run: echo '${{ steps.broken-link.outputs.output }}'
```

If you have found a Dead Link and want to automatically add it as an issue, please refer to the "[Automating Dead Link Detection](https://www.hahwul.com/2024/10/20/automating-dead-link-detection/)" article.

### Ruby Code
```ruby
require 'deadfinder'

runner = DeadFinder::Runner.new
options = runner.default_options
options['concurrency'] = 30

DeadFinder.run_url('https://www.hahwul.com/cullinan/csrf/', options)
puts DeadFinder.output

# {"https://www.hahwul.com/cullinan/csrf/" => ["https://www.hahwul.com/tag/cullinan/"]}
```

For various examples and detailed usage, including sitemap, file, and other modes, please refer to the [examples](./examples) directory in the repository.

## Usage
```
Commands:
  deadfinder file <FILE>            # Scan the URLs from File. (e.g deadfinder file urls.txt)
  deadfinder help [COMMAND]         # Describe available commands or one specific command
  deadfinder pipe                   # Scan the URLs from STDIN. (e.g cat urls.txt | deadfinder pipe)
  deadfinder sitemap <SITEMAP-URL>  # Scan the URLs from sitemap.
  deadfinder url <URL>              # Scan the Single URL.
  deadfinder version                # Show version.

Options:
  r, [--include30x], [--no-include30x]  # Include 30x redirections
  c, [--concurrency=N]                  # Number of concurrency
                                        # Default: 50
  t, [--timeout=N]                      # Timeout in seconds
                                        # Default: 10
  o, [--output=OUTPUT]                  # File to write result (e.g., json, yaml, csv)
  f, [--output-format=OUTPUT_FORMAT]    # Output format
                                        # Default: json
  H, [--headers=one two three]          # Custom HTTP headers to send with initial request
     [--worker-headers=one two three]   # Custom HTTP headers to send with worker requests
     [--user-agent=USER_AGENT]          # User-Agent string to use for requests
                                        # Default: Mozilla/5.0 (compatible; DeadFinder/1.6.1;)
  p, [--proxy=PROXY]                    # Proxy server to use for requests
     [--proxy-auth=PROXY_AUTH]          # Proxy server authentication credentials
  m, [--match=MATCH]                    # Match the URL with the given pattern
  i, [--ignore=IGNORE]                  # Ignore the URL with the given pattern
  s, [--silent], [--no-silent]          # Silent mode
  v, [--verbose], [--no-verbose]        # Verbose mode
```

## Modes
```shell
# Scan the URLs from STDIN (multiple URLs)
cat urls.txt | deadfinder pipe

# Scan the URLs from File. (multiple URLs)
deadfinder file urls.txt

# Scan the Single URL.
deadfinder url https://www.hahwul.com

# Scan the URLs from sitemap. (multiple URLs)
deadfinder sitemap https://www.hahwul.com/sitemap.xml
```

## JSON Handling
```shell
deadfinder sitemap https://www.hahwul.com/sitemap.xml \
  -o output.json
  
cat output.json | jq
```

```json
{
  "Origin URL": [
    "DeadLink URL",
    "DeadLink URL",
    "DeadLink URL"
  ]
}
```

## Contributions Welcome!

We welcome contributions from everyone! If you have an idea for an improvement or want to report a bug:

- **Fork the repository.**
- **Create a new branch** for your feature or bug fix (e.g., `feature/awesome-feature` or `bugfix/annoying-bug`).
- **Make your changes.**
- **Commit your changes** with a clear commit message.
- **Push** to the branch.
- **Submit a Pull Request (PR)** to our `main` branch.

We'll review your PR as soon as possible. Thank you for contributing to our project!

### Contributors

![](CONTRIBUTORS.svg)