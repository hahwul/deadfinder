---
title: "Usage"
weight: 2
---

This section covers the basic usage of DeadFinder and provides examples for common use cases.

## Basic Usage

### Scan a Single URL

To scan a single URL for dead links:

```bash
deadfinder url https://www.example.com
```

### Scan URLs from a File

Create a file with URLs (one per line) and scan them:

```bash
# Create urls.txt with URLs
echo "https://www.example.com" > urls.txt
echo "https://www.example.org" >> urls.txt

# Scan the file
deadfinder file urls.txt
```

### Scan from Sitemap

Scan all URLs listed in a sitemap:

```bash
deadfinder sitemap https://www.example.com/sitemap.xml
```

### Scan from STDIN (Pipe Mode)

You can pipe URLs from other commands:

```bash
cat urls.txt | deadfinder pipe
```

Or combine with other tools:

```bash
echo "https://www.example.com" | deadfinder pipe
```

## Output Options

### Save Results to File

Save the scan results to a file:

```bash
deadfinder url https://www.example.com -o results.json
```

### Different Output Formats

DeadFinder supports JSON (default), YAML, CSV, and TOML output formats:

```bash
# JSON format (default)
deadfinder url https://www.example.com -f json -o results.json

# YAML format
deadfinder url https://www.example.com -f yaml -o results.yaml

# CSV format
deadfinder url https://www.example.com -f csv -o results.csv

# TOML format
deadfinder url https://www.example.com -f toml -o results.toml
```

## Performance Options

### Adjust Concurrency

Control the number of concurrent workers (default is 50):

```bash
deadfinder url https://www.example.com --concurrency=30
```

### Set Timeout

Set the request timeout in seconds (default is 10):

```bash
deadfinder url https://www.example.com --timeout=15
```

### Combine Options

```bash
deadfinder sitemap https://www.example.com/sitemap.xml \
  --concurrency=30 \
  --timeout=15 \
  -o results.json
```

## Filtering Options

### URL Pattern Matching

Match only URLs that match a specific pattern:

```bash
deadfinder url https://www.example.com --match="api|v1|graphql"
```

### Ignore URL Patterns

Ignore URLs that match specific patterns:

```bash
deadfinder url https://www.example.com --ignore="static|images|css"
```

### Include 30x Redirections

By default, redirects (30x) are not considered as dead links. To include them:

```bash
deadfinder url https://www.example.com --include30x
```

## Network Options

### Custom Headers

Add custom HTTP headers to the initial request:

```bash
deadfinder url https://www.example.com --headers "Authorization: Bearer token"
```

Add custom headers for worker requests:

```bash
deadfinder url https://www.example.com --worker-headers "User-Agent: CustomBot"
```

### Custom User-Agent

Set a custom User-Agent string:

```bash
deadfinder url https://www.example.com --user-agent="MyBot/1.0"
```

### Proxy Configuration

Use a proxy server for requests:

```bash
deadfinder url https://www.example.com --proxy="http://localhost:8080"
```

With authentication:

```bash
deadfinder url https://www.example.com \
  --proxy="http://localhost:8080" \
  --proxy-auth="username:password"
```

## Coverage and Visualization

### Enable Coverage Analysis

Get detailed statistics about your scan:

```bash
deadfinder url https://www.example.com --coverage
```

This will show:
- Total URLs tested
- Total dead links found
- Coverage percentage

### Visualize Results

Generate a visualization of the results:

```bash
deadfinder url https://www.example.com --visualize=report.png
```

## Output Modes

### Silent Mode

Suppress progress output during scanning:

```bash
deadfinder url https://www.example.com --silent
```

### Verbose Mode

Enable detailed output for debugging:

```bash
deadfinder url https://www.example.com --verbose
```

### Debug Mode

Enable debug output for troubleshooting:

```bash
deadfinder url https://www.example.com --debug
```

## Advanced Examples

### Complete Workflow

Here's a complete example combining multiple options:

```bash
deadfinder sitemap https://www.example.com/sitemap.xml \
  --concurrency=50 \
  --timeout=10 \
  --include30x \
  --match="blog|docs" \
  --ignore="static|cdn" \
  --headers "User-Agent: DeadFinderBot" \
  --coverage \
  --visualize=report.png \
  -f json \
  -o results.json
```

### Monitoring Multiple Sites

Create a script to monitor multiple sites:

```bash
#!/bin/bash
for site in site1.com site2.com site3.com; do
  deadfinder url "https://$site" \
    --silent \
    -o "results-${site}.json"
done
```

## Shell Completion

Generate shell completion scripts for bash, zsh, or fish:

```bash
# Bash
deadfinder completion bash > /etc/bash_completion.d/deadfinder

# Zsh
deadfinder completion zsh > ~/.zsh/completion/_deadfinder

# Fish
deadfinder completion fish > ~/.config/fish/completions/deadfinder.fish
```
