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
  file <FILE>                 Scan the URLs from File (`-` for STDIN)
  url <URL>                   Scan the Single URL
  sitemap <SITEMAP-URL>       Scan the URLs from sitemap
  completion <SHELL>          Generate completion script (bash/zsh/fish)
  version                     Show version
```

## Options

| Short | Long | Default | Description |
|---|---|---|---|
| `-r` | `--include30x` | `false` | Treat 3xx responses as dead links. |
| `-c` | `--concurrency=N` | `50` | Global cap on in-flight HTTP requests. |
| | `--target-concurrency=N` | `10` | Targets scanned at once. Does **not** widen the request budget — `-c` still caps total in-flight requests. |
| `-t` | `--timeout=N` | `10` | Per-request timeout (seconds). |
| | `--method=METHOD` | `auto` | Link-check method: `auto` / `head` / `get`. `auto` sends HEAD first and confirms with GET on any 4xx/5xx (405/501 included), so no link is reported dead on a HEAD *status* alone. A HEAD that never reached the host (connect refused/timed out, DNS failure) is not re-checked — a GET cannot succeed where the TCP connect did not — so an unreachable link costs one connect timeout per attempt, not two. Documents (the target page, a sitemap) are always fetched with GET. |
| | `--retry=N` | `2` | Extra attempts for a *transient* failure (connection error, timeout, 429, 5xx), with jittered exponential backoff. A 404 is never retried. |
| | `--delay=MS` | `0` | Minimum interval between two requests to the same host. Per-host, so one slow host does not stall the others. |
| | `--accept-status=LIST` | `""` | Statuses to treat as **alive** — bare codes and inclusive ranges (`200,204,403,999`, `400-499`). Wins over `--dead-status` and over the built-in rule. |
| | `--dead-status=LIST` | `""` | Statuses to treat as **dead**, even a 2xx (a soft-404 that answers 200). Applied after `--accept-status`. |
| | `--exclude-status=LIST` | `""` | Alias of `--dead-status`. |
| `-o` | `--output=FILE` | `""` | Write structured results to FILE. `-` writes to stdout. |
| `-f` | `--output_format=FORMAT` | `json` | `json` / `yaml` / `toml` / `csv` / `sarif`. |
| `-H` | `--headers=HEADER` | `[]` | Header for the **initial** page fetch. Repeat for multiple. Format: `"Name: Value"`. |
| | `--worker_headers=HEADER` | `[]` | Header for every **link-check** request. Repeat for multiple. |
| | `--user_agent=UA` | `Mozilla/5.0 (compatible; DeadFinder/<VERSION>;)` | Override User-Agent. |
| `-p` | `--proxy=URL` | `""` | HTTP/HTTPS proxy (HTTPS uses CONNECT tunneling). |
| | `--proxy_auth=USER:PASS` | `""` | Proxy credentials (Basic). |
| `-k` | `--insecure` | `false` | Skip TLS certificate verification (not recommended). |
| `-m` | `--match=PATTERN` | `""` | Regex: only scan URLs that match. |
| `-i` | `--ignore=PATTERN` | `""` | Regex: skip URLs that match. |
| `-s` | `--silent` | `false` | Suppress the live log on stdout. |
| `-v` | `--verbose` | `false` | Log every checked URL, not just dead ones. |
| | `--debug` | `false` | Internal state / cache diagnostics. |
| | `--limit=N` | `0` | Cap input URLs (`0` = unlimited). |
| | `--check-anchors` | `false` | Verify that `#fragment` link targets exist in the linked document. Needs the response body, so it is opt-in. |
| | `--coverage` | `false` | Emit per-target coverage stats. |
| `-F` | `--fail-on-dead` | `false` | Exit `2` when any dead link or dead target was found. Off by default: a scan has always exited `0`. |
| | `--visualize=PATH` | `""` | Write a PNG status-code chart (implies `--coverage`). |
| `-h` | `--help` | | Print this option list and exit. |

## Notes

- Structured output needs `-o`. Pass `-o -` to stream the report on stdout; the live log then moves to stderr so the two never interleave (`deadfinder url X -f json -o - | jq` works without `-s`).
- Exit codes: `0` = scan completed, `1` = usage or I/O error, `2` = dead findings and `--fail-on-dead` was given. Without `--fail-on-dead` a scan that finds broken links still exits `0`.
- A scan target that is itself broken (4xx/5xx, or unreachable) is reported under a `dead_targets` key, emitted only when non-empty. Previously only links *found on* a page were reported, so a URL list whose entries all 404 produced an empty report.
- Coverage's `coverage_percentage` / `overall_coverage_percentage` are really the **dead-link ratio** (a healthy target reports `0.0`). `dead_link_percentage` / `overall_dead_link_percentage` carry the same value under the correct name; the old keys remain as deprecated aliases.
- `match` / `ignore` patterns are capped at 1024 characters, and patterns with nested quantifiers (e.g. `(a+)+`) are rejected up front to block ReDoS.
- The initial page fetch receives `--headers`; worker link-check requests receive `--worker_headers`. `--user_agent` applies to both.
- `--visualize` auto-enables `--coverage`.
- `-k` / `--insecure` turns off certificate verification for **every** HTTPS request — the initial page fetch, every link check, and the CONNECT tunnel to an HTTPS proxy. Use it only against hosts whose certificate you already know is broken (an internal CA, an expired staging cert).
