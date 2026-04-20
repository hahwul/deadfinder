+++
title = "GitHub Action"
description = "hahwul/deadfinder composite action — inputs, outputs, examples."
weight = 1
+++

`hahwul/deadfinder` is a composite action that downloads the matching release binary, verifies its sha256, and executes the scan. Runs on Linux (x86_64/aarch64) and macOS (arm64). Intel macOS runners (`macos-13`) are not supported — use `macos-latest`.

## Pin a version

Always pin a released ref. `@latest` is **not** a valid Actions ref (GitHub has no auto-resolver for it).

```yaml
- uses: hahwul/deadfinder@2        # tracks latest 2.x — gets bug-fix patches automatically
# or
- uses: hahwul/deadfinder@2.0.1    # exact pin — fully reproducible
```

The `version` input can override the binary independently of the action ref:

```yaml
- uses: hahwul/deadfinder@2
  with:
    version: "2.0.1"   # download binary from this release tag
```

## Full example

```yaml
steps:
  - name: Run DeadFinder
    uses: hahwul/deadfinder@2
    id: scan
    with:
      command: sitemap
      target: https://www.example.com/sitemap.xml
      # Optional:
      # timeout: 10
      # concurrency: 50
      # include30x: false
      # headers: "X-API-Key: secret"
      # worker_headers: "User-Agent: Deadfinder Bot"
      # user_agent: "MyBot/1.0"
      # proxy: "http://localhost:8080"
      # proxy_auth: "user:pass"
      # match: "^https://example\\.com/"
      # ignore: "\\.png$"
      # coverage: true
      # visualize: report.png
      # silent: false
      # verbose: false

  - name: Handle results
    run: echo '${{ steps.scan.outputs.output }}' | jq '.'
```

## Inputs

| Input | Required | Default | Notes |
|---|---|---|---|
| `command` | ✓ | — | `url` / `file` / `pipe` / `sitemap` |
| `target` | ✓ | — | URL, file path, or sitemap URL |
| `version` | | `latest` | Release tag; `latest` resolves to most recent release |
| `timeout` | | `10` | seconds |
| `concurrency` | | `50` | workers |
| `silent` | | `false` | string `"true"` to enable |
| `verbose` | | `false` | |
| `include30x` | | `false` | |
| `headers` | | `""` | comma-separated `"Key: Value"` pairs |
| `worker_headers` | | `""` | headers for link-check requests |
| `user_agent` | | `""` | overrides default UA |
| `proxy` | | `""` | HTTP/HTTPS proxy URL |
| `proxy_auth` | | `""` | `user:pass` |
| `match` | | `""` | regex |
| `ignore` | | `""` | regex |
| `coverage` | | `false` | |
| `visualize` | | `""` | file path (implies coverage) |

## Outputs

| Output | Shape |
|---|---|
| `output` | Compact JSON string of the scan result (same shape as `-f json` output). |

Consume with `fromJSON()`:

```yaml
- run: |
    echo "Dead links: ${{ fromJSON(steps.scan.outputs.output).summary }}"
```

## Migrating from v1

The v1 action was Docker-based and bundled the Ruby gem. v2 is a composite action that downloads the Crystal binary directly. All v1 inputs are preserved. `worker_headers` was previously undeclared but wired through args — it's now a formal input. `version` is new. No inputs were renamed or removed.

Pin to `@1.10.0` to keep the v1 behavior; use `@2` (or pin a specific 2.x tag like `@2.0.1`) for v2.
