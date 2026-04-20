+++
title = "Filtering"
description = "Regex match/ignore, 3xx inclusion, URL limit."
weight = 3
+++

# Filtering

## `--match=PATTERN` / `--ignore=PATTERN`

Regex applied to every discovered URL before it's fetched. Each pattern has a 1-second timeout to prevent ReDoS.

```bash
# Only check internal links
deadfinder sitemap https://www.example.com/sitemap.xml \
  --match='^https://(www\.)?example\.com/'

# Skip media files
deadfinder url https://www.example.com \
  --ignore='\.(png|jpg|gif|webp|mp4)$'
```

Using both: `--match` is applied first, then `--ignore`.

## `--include30x`

By default, 3xx redirects are treated as healthy (the destination is what matters). Enable this flag to mark them as dead too:

```bash
deadfinder url https://www.example.com --include30x
```

Use this when your policy is "redirects are technical debt" rather than "follow the redirect chain".

## `--limit=N`

Cap the number of URLs scanned per invocation (useful for quick smoke tests of a large sitemap):

```bash
deadfinder sitemap https://www.example.com/sitemap.xml --limit=50
```

Applies to the input list (file lines, STDIN lines, or sitemap `<loc>` entries). Not to discovered child links on each page.

## `--concurrency=N` / `--timeout=N`

Not filters per se, but the other knobs you'll reach for:

- `--concurrency=50` (default) — number of parallel workers.
- `--timeout=10` (default, seconds) — per-request connect + read timeout.

Ramp concurrency down on rate-limited targets; up on fast internal scans.
