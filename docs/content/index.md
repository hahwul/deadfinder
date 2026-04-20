+++
title = "DeadFinder"
description = "Find dead (broken) links in web pages, URL lists, and sitemaps."
+++

# DeadFinder

Find dead (broken) links in web pages, URL lists, and sitemaps. Fast native CLI written in Crystal with fiber-based concurrency.

## Why DeadFinder

- **Fast**: fiber-based concurrent workers scan hundreds of links in parallel.
- **Ergonomic**: one binary, no runtime dependencies.
- **Structured output**: JSON / YAML / TOML / CSV — or attach as a GitHub Action output.
- **Coverage report**: track dead-link ratio per target with `--coverage`.

## Install

```bash
# Homebrew
brew install deadfinder

# Docker
docker run ghcr.io/hahwul/deadfinder:latest deadfinder url https://example.com

# Prebuilt binary — pick your platform on the Releases page
# https://github.com/hahwul/deadfinder/releases/latest
```

See [Installation](/docs/getting-started/installation/) for every channel (Nix, build from source, etc).

## First scan

```bash
deadfinder url https://your-site.example
deadfinder sitemap https://your-site.example/sitemap.xml
cat urls.txt | deadfinder pipe
```

See [Quick Start](/docs/getting-started/quickstart/) for more.

## Continuous integration

Run DeadFinder on every push via the official GitHub Action:

```yaml
- uses: hahwul/deadfinder@2.0.0
  with:
    command: sitemap
    target: https://www.example.com/sitemap.xml
```

See [GitHub Action](/docs/integration/github-action/) for the full input reference.

---

DeadFinder 2.0+ is written in Crystal. v1.x (Ruby gem) lives on the [`legacy/v1`](https://github.com/hahwul/deadfinder/tree/legacy/v1) branch and receives bug-fix updates only.
