# Changelog

All notable changes are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versioning follows [SemVer](https://semver.org/).

## [Unreleased]

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

[Unreleased]: https://github.com/hahwul/deadfinder/compare/2.0.0...HEAD
[2.0.0]: https://github.com/hahwul/deadfinder/releases/tag/2.0.0
