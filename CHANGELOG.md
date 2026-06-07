# Changelog

All notable changes are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versioning follows [SemVer](https://semver.org/).

## [Unreleased]

### Changed
- Multi-target scans (`pipe`/`file`/`sitemap`) now attribute a shared broken link to **every** page that references it, not just the first page scanned, and per-target coverage counts each page's own links. Internally the global "already-seen" URL set became a URL→status cache, so each link is still fetched at most once. Previously a 404 referenced by pages A and B was reported only under A and skewed B's coverage.

### Fixed
- `--concurrency 0` (or any value `< 1`) no longer hangs forever. The CLI rejects it up front and the runner defensively clamps to at least one worker. `--timeout`, `--limit`, and `--output_format` are likewise validated instead of silently hanging, failing every request, or emitting an unexpected format.
- `file` subcommand prints a clear "file not found" error instead of dumping a Crystal stack trace for a missing path.
- Sitemap parsing no longer scans child-sitemap `.xml` files as if they were HTML pages (sitemap-index double-processing), and extracts `<loc>` namespace-agnostically so the legacy Google `0.84` sitemap namespace is no longer silently dropped.
- TOML output escapes raw control characters (newline/CR/etc.), so a URL containing embedded control bytes no longer produces unparseable TOML.
- Proxy handling: a bare `host:port` (e.g. `127.0.0.1:8080`) is now used as a proxy instead of silently connecting directly; unsupported proxy schemes (e.g. `socks5://`) are rejected with a clear error; the HTTPS-CONNECT tunnel's DNS/connect/write are bounded by `--timeout` so an unreachable proxy can't hang past the configured timeout; and the CONNECT success check matches the real `200` status token instead of any line merely containing "200".
- A `--match`/`--ignore` pattern that backtracks catastrophically at match time (e.g. `(a|a)*`) is caught and reported as an invalid pattern instead of aborting the whole target scan; the static ReDoS guard also covers `{n,m}`-quantifier nested shapes like `(\w{2,5})+`.
- A user-supplied `User-Agent` via `-H`/`--worker_headers` is honored instead of being overwritten by the default.
- Obfuscated pseudo-scheme links with embedded tab/newline (e.g. `java<TAB>script:`) are filtered like browsers do, instead of being turned into bogus request targets.

## [2.0.2]

### Fixed
- `action.yml`: save the downloaded release tarball under its real filename (`deadfinder-linux-x86_64.tar.gz` etc.) instead of a generic `deadfinder.tar.gz`, so `sha256sum -c` can resolve the path referenced inside the sidecar. Composite-action callers hit `sha256sum: deadfinder-linux-x86_64.tar.gz: No such file or directory` right after a successful download — the earlier 2.0.0 YAML parser error was masking this. Surfaced by owasp-noir/noir run #24651380673.

## [2.0.1]

### Fixed
- `action.yml`: quote the `version` input description so its embedded `(default: latest)` doesn't trip strict YAML parsers used by the GitHub Actions runner. Caller workflows on `uses: hahwul/deadfinder@2.0.0` saw `Mapping values are not allowed in this context.` and failed at job startup.
- `scripts/version_update.cr`: constrain `^version:\s*.+$/m` patterns with `[^\n]+` — Crystal's `m` flag enables both line-anchor and DOTALL semantics, so `.+$` greedily ate the rest of the file and truncated `shard.yml`/`snap/snapcraft.yaml`/`aur/PKGBUILD` on the first 2.0.1 bump attempt.

## [2.0.0] — Crystal rewrite

### Added
- Crystal implementation (fiber-based concurrency via `spawn` + `Channel`) replaces the Ruby gem as the supported runtime.
- Multi-platform release binaries auto-attached on every GitHub Release: linux x86_64/aarch64 (static/musl), macOS arm64. Each tarball ships alongside a `.sha256` sidecar. (Intel macOS isn't shipped as a prebuilt — see [installation docs](https://hahwul.github.io/deadfinder/docs/getting-started/installation/) for source/Rosetta options.)
- Cross-implementation compatibility harness (`spec/compat/`) — black-box golden files captured from v1 Ruby output, locking the CLI/output contract for Crystal.
- GitHub Action migrated to a composite action that downloads the release binary and verifies its sha256 before running. The `version` input (defaulting to `latest`) lets callers pin a specific release. `worker_headers` is now a first-class input.
- Docker image rebuilt on Crystal static binary (`alpine:3.21` runtime, `<15 MB`). OCI labels, semver tags (`2.0.0` / `2.0` / `latest`), and keyless cosign signatures on every published tag.

### Changed
- Repository layout: Crystal at the root. `src/`, `spec/`, `shard.yml`, `shard.lock` live at the top level; the old `crystal/` subdirectory is gone.
- CLI flag behavior aligns with Ruby v1 exactly — the compat harness enforces this. No user-visible flag renames.
- `--silent` default remains `false`; `-s` opts in. (An earlier Crystal port defaulted silent to `true`; that regression was fixed before the 2.0.0 cut.)
- `--user_agent`, `--proxy_auth`, `--worker_headers` use underscores (as implemented). Prior dashed forms never worked reliably in the old Docker-based action; the new composite action passes the correct names.

### Fixed
- Resolved URLs preserve the base URL's non-default port for both `href="/path"` and `href="relative/path"` shapes (was dropping the port in the Crystal port).
- Docker-based GitHub Action chain: previously relied on a Ruby-gem image and a brittle entrypoint.sh; replaced with a composite action that downloads the release binary directly.

### Removed
- Ruby gem publishing from `main`. The gem continues on the [`legacy/v1`](https://github.com/hahwul/deadfinder/tree/legacy/v1) branch for bug-fix and security releases only.
- `lib/`, `bin/`, `Gemfile`, `Gemfile.lock`, `Rakefile`, `deadfinder.gemspec`, `gemset.nix`, `.rubocop.yml`, `ruby-version`, Ruby-based `flake.nix`, and the legacy Ruby spec suite.
- `github-action/Dockerfile` + `entrypoint.sh` (replaced by composite action in `action.yml`).

### Migration from v1

| You had | Switch to |
|---|---|
| `gem install deadfinder` | `brew install deadfinder` or prebuilt binary from the release |
| `bundle exec deadfinder …` | Same binary on `PATH`, no bundler |
| Docker image (same name) | No change — the image now ships the Crystal binary |
| `uses: hahwul/deadfinder@…` | No change — the action now uses the Crystal binary under the hood |
| `require 'deadfinder'` | Library usage is gone from main. If you depend on it, pin to a v1 gem release or use the CLI. |

If you need a bugfix in v1, open an issue/PR against the [`legacy/v1`](https://github.com/hahwul/deadfinder/tree/legacy/v1) branch.

---

History prior to 2.0.0 was not maintained in this file. See [GitHub Releases](https://github.com/hahwul/deadfinder/releases?q=prerelease%3Afalse) and the [`legacy/v1`](https://github.com/hahwul/deadfinder/tree/legacy/v1) branch for v1 release history.

[Unreleased]: https://github.com/hahwul/deadfinder/compare/2.0.2...HEAD
[2.0.2]: https://github.com/hahwul/deadfinder/releases/tag/2.0.2
[2.0.1]: https://github.com/hahwul/deadfinder/releases/tag/2.0.1
[2.0.0]: https://github.com/hahwul/deadfinder/releases/tag/2.0.0
