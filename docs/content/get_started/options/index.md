---
title: "Options Reference"
weight: 3
---

This page provides a complete reference of all command-line options available in DeadFinder.

## Commands

DeadFinder supports the following commands:

- `url <URL>` - Scan a single URL
- `file <FILE>` - Scan URLs from a file
- `sitemap <SITEMAP-URL>` - Scan URLs from a sitemap
- `pipe` - Scan URLs from STDIN
- `completion <SHELL>` - Generate shell completion script
- `version` - Show version information

## Global Options

These options are available for all scan commands (`url`, `file`, `sitemap`, `pipe`).

### Performance Options

| Option | Alias | Type | Default | Description |
|--------|-------|------|---------|-------------|
| `--concurrency` | `-c` | Number | 50 | Number of concurrent workers |
| `--timeout` | `-t` | Number | 10 | Timeout in seconds for each request |

### Output Options

| Option | Alias | Type | Default | Description |
|--------|-------|------|---------|-------------|
| `--output` | `-o` | String | - | File path to write results |
| `--output-format` | `-f` | String | json | Output format: json, yaml, or csv |
| `--silent` | `-s` | Boolean | false | Suppress progress output |
| `--verbose` | - | Boolean | false | Enable verbose output |
| `--debug` | - | Boolean | false | Enable debug output |

### HTTP Options

| Option | Alias | Type | Default | Description |
|--------|-------|------|---------|-------------|
| `--include30x` | `-r` | Boolean | false | Include 30x redirections as dead links |
| `--headers` | `-H` | Array | [] | Custom HTTP headers for initial request |
| `--worker-headers` | - | Array | [] | Custom HTTP headers for worker requests |
| `--user-agent` | - | String | Mozilla/5.0... | User-Agent string for requests |
| `--proxy` | `-p` | String | - | Proxy server URL |
| `--proxy-auth` | - | String | - | Proxy authentication (username:password) |

### Filtering Options

| Option | Alias | Type | Default | Description |
|--------|-------|------|---------|-------------|
| `--match` | `-m` | String | - | Only include URLs matching this regex pattern |
| `--ignore` | `-i` | String | - | Ignore URLs matching this regex pattern |

### Analysis Options

| Option | Alias | Type | Default | Description |
|--------|-------|------|---------|-------------|
| `--coverage` | - | Boolean | false | Enable coverage analysis |
| `--visualize` | - | String | - | Generate visualization image file |

## Examples

### Performance Tuning

Increase concurrency for faster scans:

```bash
deadfinder url https://example.com --concurrency=100
```

Set a longer timeout for slow sites:

```bash
deadfinder url https://example.com --timeout=30
```

### Output Control

Save results in YAML format:

```bash
deadfinder url https://example.com -f yaml -o results.yaml
```

Run in silent mode:

```bash
deadfinder url https://example.com --silent
```

### HTTP Configuration

Add custom headers:

```bash
deadfinder url https://example.com \
  --headers "Authorization: Bearer token" \
  --headers "X-API-Key: secret"
```

Use a proxy:

```bash
deadfinder url https://example.com \
  --proxy="http://localhost:8080" \
  --proxy-auth="user:pass"
```

Custom User-Agent:

```bash
deadfinder url https://example.com --user-agent="MyBot/1.0"
```

### Filtering

Match only API endpoints:

```bash
deadfinder url https://example.com --match="api|v1|v2"
```

Ignore static resources:

```bash
deadfinder url https://example.com --ignore="css|js|png|jpg"
```

Combine filters:

```bash
deadfinder url https://example.com \
  --match="docs|blog" \
  --ignore="static|cdn"
```

### Analysis

Enable coverage analysis:

```bash
deadfinder url https://example.com --coverage
```

Generate visualization:

```bash
deadfinder url https://example.com --visualize=report.png
```

Both together:

```bash
deadfinder url https://example.com --coverage --visualize=report.png
```

## Output Format Details

### JSON Format

The JSON output follows this structure:

```json
{
  "https://example.com": [
    "https://example.com/broken-link1",
    "https://example.com/broken-link2"
  ],
  "coverage": {
    "total_tested": 100,
    "total_dead": 5,
    "overall_coverage_percentage": 95.0
  }
}
```

### YAML Format

The YAML output provides the same information in YAML format:

```yaml
---
https://example.com:
  - https://example.com/broken-link1
  - https://example.com/broken-link2
coverage:
  total_tested: 100
  total_dead: 5
  overall_coverage_percentage: 95.0
```

### CSV Format

The CSV output is a flat structure:

```csv
target,url
https://example.com,https://example.com/broken-link1
https://example.com,https://example.com/broken-link2
```

## Shell Completion

DeadFinder supports shell completion for bash, zsh, and fish. Generate the completion script for your shell:

### Bash

```bash
deadfinder completion bash > /etc/bash_completion.d/deadfinder
```

Or add to your `.bashrc`:

```bash
eval "$(deadfinder completion bash)"
```

### Zsh

```bash
deadfinder completion zsh > ~/.zsh/completion/_deadfinder
```

Make sure your `.zshrc` includes:

```bash
fpath=(~/.zsh/completion $fpath)
autoload -Uz compinit && compinit
```

### Fish

```bash
deadfinder completion fish > ~/.config/fish/completions/deadfinder.fish
```

## Environment Variables

DeadFinder doesn't use environment variables for configuration, but you can set defaults in your shell profile:

```bash
# Example .bashrc/.zshrc aliases
alias df='deadfinder'
alias df-silent='deadfinder --silent'
alias df-verbose='deadfinder --verbose'
```
