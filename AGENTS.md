# DeadFinder — Agent Guide

DeadFinder is a CLI tool that finds broken links in web pages, sitemaps, and URL lists. It is written in **Crystal** (v2.x+). The legacy Ruby v1.x implementation lives on the `legacy/v1` branch.

Reference this file first; fall back to the source only when something here is stale.

## Prerequisites

- Crystal >= 1.19.1
- cmake, make, g++ (for building the `lexbor` HTML parser)

## Bootstrap

```bash
shards install
```

## Build

```bash
# Debug (fast compile, slower binary)
crystal build src/cli_main.cr -o deadfinder

# Release (slow compile, fast binary)
crystal build src/cli_main.cr -o deadfinder --release --no-debug
```

## Test

```bash
# Unit specs
crystal spec

# Cross-implementation compat harness (golden files from v1 Ruby output)
BIN="./deadfinder" ruby spec/compat/run.rb
```

The compat harness requires `toml-rb` (`gem install toml-rb`) and spins up a local fixture HTTP server on a random port.

## Run

```bash
./deadfinder url https://example.com
./deadfinder file urls.txt
cat urls.txt | ./deadfinder pipe
./deadfinder sitemap https://example.com/sitemap.xml
```

Full flag list lives in `src/deadfinder/cli.cr` (the `OptionParser` block).

## Layout

```
src/
├── cli_main.cr                # binary entry
├── deadfinder.cr              # module root (run_* dispatchers, output serialization)
└── deadfinder/
    ├── cli.cr                 # OptionParser + subcommand routing
    ├── types.cr               # Options + coverage structs
    ├── runner.cr              # fiber workers, link extraction, HTTP calls
    ├── http_client.cr         # HTTP::Client wrapper (proxy, CONNECT tunneling)
    ├── utils.cr               # URL resolution helpers
    ├── url_pattern_matcher.cr # match/ignore regex with 1s timeout
    ├── logger.cr              # silent/verbose/debug gating
    ├── completion.cr          # bash/zsh/fish completion generators
    ├── visualizer.cr          # PNG coverage chart (stumpy_png)
    └── version.cr

spec/
├── deadfinder_spec.cr
├── spec_helper.cr
├── deadfinder/                # unit specs per module
└── compat/                    # black-box harness (v1 golden files)
```

## Conventions

- Output surface is stable: CLI flags, subcommands, and JSON/YAML/TOML/CSV shapes match v1 Ruby. The golden files in `spec/compat/golden/` lock this contract. New report keys (`dead_targets`) and new coverage fields are additive and emitted only when non-empty, and every new behaviour that would change the frozen surface is behind an opt-in flag. `spec/compat/run.rb` asserts the binary exits **0**, which is why `--fail-on-dead` cannot be the default.
- `cli.cr`'s `OptionParser` block is the single source of truth for the CLI surface. `Completion::FLAGS` mirrors it and `spec/deadfinder/completion_spec.cr` scrapes the parser out of the source to fail the moment they drift — so adding a flag means adding it there, and to `README.md`, `docs/content/docs/reference/cli-flags.md` and `action.yml`. Keep the `parser.on(...)` help strings free of interpolation; the drift spec compares them verbatim.
- `-c`/`--concurrency` is a **global** cap on in-flight HTTP requests, held as permits in `Runner.permits`. `--target-concurrency` decides how many pages compete for that budget and must never multiply it. A fiber must not hold a permit while sleeping or while waiting on another fiber's request — `resolve_status`'s in-flight registry and `fetch_status_with_retries`' backoff both deliberately wait outside the permit.
- Any fiber that logs on a target's behalf must inherit that target's log buffer via `Logger.with_buffer(Logger.current_buffer)`, or its lines land in the middle of another target's block once `--target-concurrency > 1`.
- Link status checks use HEAD first (`--method auto`) but a dead link is never reported on a HEAD alone — a GET confirms it. Documents (target pages, sitemaps) are always fetched with GET; their body is the point.
- Resolved URLs must preserve the base URL's port. Port preservation is delegated to `base_uri.resolve` in `utils.cr::generate_url`; the regression specs live in `spec/deadfinder/utils_spec.cr` ("preserves non-default port…"). This was a v1 pain point; don't regress.
- Silent default is `false` — the CLI emits logs by default. `-s` / `--silent` opts in.
- Redirects are followed when fetching a **document** (a scan target page, a sitemap) but never when **checking a link** — there the `30x` is the result `--include30x` acts on. `HttpClient.fetch` takes the hop count per call site; `runner.cr::check_url` deliberately passes none. The regression spec is `spec/deadfinder/runner_spec.cr` ("still reports link redirects verbatim without following them").

## CI

- `.github/workflows/compat.yml` — Crystal build + compat harness on every PR
- `.github/workflows/crystal-release.yml` — release-triggered builds for linux x86_64/aarch64 and macOS arm64; uploads tar.gz + sha256 as release assets
- `.github/workflows/docker-build.yml` / `docker-ghcr.yml` — multi-arch image builds (Crystal static binary in Alpine)

## Distribution channels

| Channel | How it picks up a new release |
|---|---|
| GitHub Release binaries | `crystal-release.yml` auto-uploads on `release: published` |
| Docker (`ghcr.io/hahwul/deadfinder`) | `docker-ghcr.yml` on push to main / release |
| Homebrew (homebrew-core) | Manual PR via `brew bump-formula-pr` after tagging |
| GitHub Action (`hahwul/deadfinder@<tag>`) | `action.yml` in repo root; downloads the release binary |

## Legacy (Ruby v1) branch

Gem releases still happen on `legacy/v1`. Bug-fix and security updates only — no new features. Do not port v1 changes to main unless they are true behavioral fixes that should also apply to Crystal.
