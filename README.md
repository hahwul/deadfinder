<div align="center">
      <img alt="DeadFinder Logo" src="docs/static/images/deadfinder.webp" width="200px;">
  <p>Find dead-links (broken links)</p>
</div>

<p align="center">
<a href="https://github.com/hahwul/deadfinder/releases">
<img src="https://img.shields.io/github/v/release/hahwul/deadfinder?style=for-the-badge&color=black&labelColor=black&logo=web"></a>
<a href="https://crystal-lang.org">
<img src="https://img.shields.io/badge/Crystal-000000?style=for-the-badge&logo=crystal&logoColor=white"></a>
</p>

<p align="center">
  <a href="https://deadfinder.hahwul.com">Documentation</a> •
  <a href="https://deadfinder.hahwul.com/docs/getting-started/installation/">Installation</a> •
  <a href="https://deadfinder.hahwul.com/docs/integration/github-action/">Github Action</a> •
  <a href="#contributing">Contributing</a> •
  <a href="CHANGELOG.md">Changelog</a>
</p>

Dead link (broken link) means a link within a web page that cannot be connected. These links can have a negative impact to SEO and Security. This tool makes it easy to identify and modify.

![](https://github.com/user-attachments/assets/92129de9-90c6-41e0-a424-883fe30858f6)

> **Looking for v1 (Ruby gem)?** It now lives on the [`legacy/v1`](https://github.com/hahwul/deadfinder/tree/legacy/v1) branch and continues to publish the `deadfinder` gem for bug-fix and security releases. `main` hosts the Crystal rewrite (v2+).

## Installation

### Homebrew
```bash
brew install deadfinder
# https://formulae.brew.sh/formula/deadfinder
```

### Docker
```bash
docker run ghcr.io/hahwul/deadfinder:latest deadfinder url https://example.com
```

### Prebuilt binary
Download the archive for your platform from the [latest release](https://github.com/hahwul/deadfinder/releases/latest), extract, and place `deadfinder` on your `PATH`.

### Nix
```bash
nix run github:hahwul/deadfinder
nix profile install github:hahwul/deadfinder
nix develop github:hahwul/deadfinder
```

### Build from source
Requires Crystal >= 1.19.1 and `cmake` (for the `lexbor` HTML parser's postinstall — without it `shards install` fails with `'cmake': No such file or directory`).

```bash
# macOS
brew install crystal cmake

# Debian / Ubuntu
sudo apt install crystal cmake
```

```bash
shards install
crystal build src/cli_main.cr -o deadfinder --release
# or: just build
```

## Using In
### CLI
```bash
deadfinder sitemap https://www.hahwul.com/sitemap.xml
```

### GitHub Action
Pin a specific release tag. `@latest` is **not** a valid Actions ref.

```yml
steps:
- name: Run DeadFinder
  uses: hahwul/deadfinder@v2       # tracks the latest 2.x — pin a specific tag (e.g. @2.0.2) for stricter reproducibility
  id: broken-link
  with:
    command: sitemap           # url / file / sitemap / pipe
    target: https://www.hahwul.com/sitemap.xml
    # timeout: 10
    # concurrency: 50
    # silent: false
    # headers: "X-API-Key: 123444"
    # worker_headers: "User-Agent: Deadfinder Bot"
    # include30x: false
    # user_agent: "Apple"
    # proxy: "http://localhost:8070"
    # proxy_auth: "id:pw"
    # match:  ""
    # ignore: ""
    # coverage: true
    # visualize: report.png

- name: Output Handling
  run: echo '${{ steps.broken-link.outputs.output }}'
```

If you have found a Dead Link and want to automatically add it as an issue, please refer to the "[Automating Dead Link Detection](https://www.hahwul.com/2024/10/20/automating-dead-link-detection/)" article.

## Usage
```
Usage: deadfinder <command> [options]

Commands:
  pipe                        Scan the URLs from STDIN
  file <FILE>                 Scan the URLs from File
  url <URL>                   Scan the Single URL
  sitemap <SITEMAP-URL>       Scan the URLs from sitemap
  completion <SHELL>          Generate completion script (bash/zsh/fish)
  version                     Show version

Options:
  -r, --include30x                 Include 30x redirections as dead links
  -c, --concurrency=N              Number of concurrent workers (default: 50)
  -t, --timeout=N                  Timeout in seconds (default: 10)
  -o, --output=FILE                File to write results
  -f, --output_format=FORMAT       Output format: json, yaml, toml, csv (default: json)
  -H, --headers=HEADER             Custom HTTP headers for initial request
      --worker_headers=HEADER      Custom HTTP headers for worker requests
      --user_agent=UA              User-Agent string
  -p, --proxy=PROXY                Proxy server (HTTP and HTTPS CONNECT)
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

## Modes
```bash
# Scan the URLs from STDIN (multiple URLs)
cat urls.txt | deadfinder pipe

# Scan the URLs from a file
deadfinder file urls.txt

# Scan a single URL
deadfinder url https://www.hahwul.com

# Scan the URLs from a sitemap
deadfinder sitemap https://www.hahwul.com/sitemap.xml
```

## JSON Handling
```bash
deadfinder sitemap https://www.hahwul.com/sitemap.xml -o output.json
cat output.json | jq
```

```json
{
  "Target URL": [
    "DeadLink URL",
    "DeadLink URL",
    "DeadLink URL"
  ]
}
```

With `--coverage`:

```bash
deadfinder sitemap https://www.hahwul.com/sitemap.xml --coverage -o output.json
```

```json
{
  "dead_links": {
    "Target URL": ["DeadLink URL 1", "DeadLink URL 2"]
  },
  "coverage": {
    "targets": {
      "Target URL": {
        "total_tested": 14,
        "dead_links": 7,
        "coverage_percentage": 50.0
      }
    },
    "summary": {
      "total_tested": 14,
      "total_dead": 7,
      "overall_coverage_percentage": 50.0
    }
  }
}
```

## Shell Completion
```bash
deadfinder completion bash > /etc/bash_completion.d/deadfinder
deadfinder completion zsh  > ~/.zsh/completion/_deadfinder
deadfinder completion fish > ~/.config/fish/completions/deadfinder.fish
```

## Contributing

Contributions are welcome! If you have an idea for an improvement or want to report a bug:

- **Fork the repository.**
- **Create a new branch** for your feature or bug fix (e.g., `feature/awesome-feature` or `bugfix/annoying-bug`).
- **Make your changes.**
- **Commit your changes** with a clear message.
- **Push** to the branch.
- **Submit a Pull Request (PR)** to our `main` branch.

### Contributors

![](docs/static/images/CONTRIBUTORS.svg)
