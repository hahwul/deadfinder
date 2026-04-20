+++
title = "Quick Start"
description = "Run your first DeadFinder scan and read its output."
weight = 2
+++

# Quick Start

## Scan a single URL

```bash
deadfinder url https://www.example.com
```

The terminal shows discovered links and their status:

```
▶ Fetching https://www.example.com
  ● Discovered 12 URLs, currently checking them. [anchor:8 / link:4]
  ├── ✓ [200] https://www.example.com/about
  ├── ✘ [404] https://www.example.com/old-page
  └── ● Task completed
```

Exit code is `0` even when dead links exist — parse the output to make a build pass/fail decision.

## Structured output

Write JSON to a file:

```bash
deadfinder url https://www.example.com -o output.json
cat output.json
```

```json
{
  "https://www.example.com": [
    "https://www.example.com/old-page"
  ]
}
```

YAML, TOML, CSV are available via `-f <format>`. See [Output formats](/docs/usage/output-formats/).

## Scan a sitemap

```bash
deadfinder sitemap https://www.example.com/sitemap.xml -o results.json
```

## Scan many URLs

From a file:

```bash
cat > urls.txt <<'EOF'
https://www.example.com
https://docs.example.com
EOF

deadfinder file urls.txt -o results.json
```

From STDIN:

```bash
printf 'https://www.example.com\nhttps://docs.example.com\n' \
  | deadfinder pipe -o results.json
```

## Coverage report

`--coverage` adds a per-target summary with dead-link percentage:

```bash
deadfinder sitemap https://www.example.com/sitemap.xml --coverage -o results.json
```

Optionally render a PNG chart:

```bash
deadfinder sitemap https://www.example.com/sitemap.xml --coverage --visualize report.png
```

## Next

- [Subcommands](/docs/usage/subcommands/)
- [Output formats](/docs/usage/output-formats/)
- [CLI flags reference](/docs/reference/cli-flags/)
