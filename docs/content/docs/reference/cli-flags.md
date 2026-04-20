+++
title = "CLI Flags"
description = "Complete reference for every deadfinder option."
weight = 1
+++

Run `deadfinder --help` for the live help text. This page is the documented contract.

## Synopsis

```
deadfinder <command> [options]

Commands:
  pipe                        Scan the URLs from STDIN
  file <FILE>                 Scan the URLs from File
  url <URL>                   Scan the Single URL
  sitemap <SITEMAP-URL>       Scan the URLs from sitemap
  completion <SHELL>          Generate completion script (bash/zsh/fish)
  version                     Show version
```

## Options

| Short | Long | Default | Description |
|---|---|---|---|
| `-r` | `--include30x` | `false` | Treat 3xx responses as dead links. |
| `-c` | `--concurrency=N` | `50` | Number of concurrent workers. |
| `-t` | `--timeout=N` | `10` | Per-request timeout (seconds). |
| `-o` | `--output=FILE` | `""` | Write structured results to FILE. |
| `-f` | `--output_format=FORMAT` | `json` | `json` / `yaml` / `toml` / `csv`. |
| `-H` | `--headers=HEADER` | `[]` | Header for the **initial** page fetch. Repeat for multiple. Format: `"Name: Value"`. |
| | `--worker_headers=HEADER` | `[]` | Header for every **link-check** request. Repeat for multiple. |
| | `--user_agent=UA` | `Mozilla/5.0 (compatible; DeadFinder/<VERSION>;)` | Override User-Agent. |
| `-p` | `--proxy=URL` | `""` | HTTP/HTTPS proxy (HTTPS uses CONNECT tunneling). |
| | `--proxy_auth=USER:PASS` | `""` | Proxy credentials (Basic). |
| `-m` | `--match=PATTERN` | `""` | Regex: only scan URLs that match. |
| `-i` | `--ignore=PATTERN` | `""` | Regex: skip URLs that match. |
| `-s` | `--silent` | `false` | Suppress the live log on stdout. |
| `-v` | `--verbose` | `false` | Log every checked URL, not just dead ones. |
| | `--debug` | `false` | Internal state / cache diagnostics. |
| | `--limit=N` | `0` | Cap input URLs (`0` = unlimited). |
| | `--coverage` | `false` | Emit per-target coverage stats. |
| | `--visualize=PATH` | `""` | Write a PNG status-code chart (implies `--coverage`). |

## Notes

- Structured output is **file-only**: you must set `-o`. stdout is reserved for the live log.
- `match` / `ignore` regexes each run under a 1-second timeout to block ReDoS.
- The initial page fetch receives `--headers`; worker link-check requests receive `--worker_headers`. `--user_agent` applies to both.
- `--visualize` auto-enables `--coverage`.
