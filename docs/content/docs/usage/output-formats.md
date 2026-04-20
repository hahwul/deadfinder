+++
title = "Output Formats"
description = "JSON, YAML, TOML, CSV, coverage reports, and PNG visualization."
weight = 2
+++

DeadFinder writes results only when `-o <FILE>` is set (stdout stays human-readable log). Pick the format with `-f <format>`.

| Flag | Format |
|---|---|
| `-f json` (default) | pretty JSON |
| `-f yaml` / `-f yml` | YAML |
| `-f toml` | TOML |
| `-f csv` | CSV with `target,url` columns |

## Basic shape

Same across JSON / YAML / TOML:

```json
{
  "https://www.example.com": [
    "https://www.example.com/broken-link-1",
    "https://www.example.com/broken-link-2"
  ]
}
```

CSV:

```csv
target,url
https://www.example.com,https://www.example.com/broken-link-1
https://www.example.com,https://www.example.com/broken-link-2
```

## Coverage mode

Add `--coverage` to include per-target statistics:

```bash
deadfinder sitemap https://www.example.com/sitemap.xml --coverage -o out.json
```

```json
{
  "dead_links": {
    "https://www.example.com": ["https://www.example.com/broken-link-1"]
  },
  "coverage": {
    "targets": {
      "https://www.example.com": {
        "total_tested": 100,
        "dead_links": 5,
        "coverage_percentage": 5.0,
        "status_counts": {"404": 3, "500": 2}
      }
    },
    "summary": {
      "total_tested": 100,
      "total_dead": 5,
      "overall_coverage_percentage": 5.0,
      "overall_status_counts": {"404": 3, "500": 2}
    }
  }
}
```

## PNG visualization

```bash
deadfinder sitemap https://www.example.com/sitemap.xml --visualize report.png
```

`--visualize` implies `--coverage`. Output is a stacked bar chart of status codes per target.

## Stdout vs file

Structured output requires `-o`. Without it the tool emits a live log to stdout only. Use `-s` / `--silent` to suppress the log entirely (for example when you're only interested in the file output).

```bash
deadfinder url https://www.example.com -o out.json -s
```
