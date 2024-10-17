# DeadFinder

Dead link (broken link) means a link within a web page that cannot be connected. These links can have a negative impact to SEO and Security. This tool makes it easy to identify and modify.

![](https://github.com/user-attachments/assets/92129de9-90c6-41e0-a424-883fe30858f6)

## Installation
### Install with Gem
```bash
gem install deadfinder

# https://rubygems.org/gems/deadfinder
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
  uses: hahwul/deadfinder@1.5.0
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

- name: Output Handling
  run: echo '${{ steps.broken-link.outputs.output }}'
```

### Ruby Code
```ruby
require 'deadfinder'

app = DeadFinderRunner.new
options = app.default_options
options['concurrency'] = 30

result = app.run('https://www.hahwul.com/2022/09/30/deadfinder/', options)
puts result
```

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
  o, [--output=OUTPUT]                  # File to write JSON result
  H, [--headers=one two three]          # Custom HTTP headers to send with request
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
- **Submit a Pull Request (PR)** to our `dev` branch.

We'll review your PR as soon as possible. Thank you for contributing to our project!

### Contributors

![](CONTRIBUTORS.svg)