# Changelog

All notable changes are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versioning follows [SemVer](https://semver.org/).

## [Unreleased]

### Added
- `-F` / `--fail-on-dead` exits `2` when a scan finds a dead link or a dead target, so a CI job can finally gate on a broken link. Opt-in: a scan has always exited `0` and `spec/compat/run.rb` locks that, so the default is unchanged. `1` stays reserved for usage and I/O errors. The GitHub Action gained a matching `fail_on_dead` input; it holds the scan's status until the report has been published as a step output, then re-raises it.
- `-o -` streams the report to STDOUT instead of creating a file literally named `-`, and moves the live log to STDERR in that mode so `deadfinder url X -f json -o - | jq` works without `--silent`.
- A scan target that is itself broken (4xx/5xx, or unreachable) is now reported under a new top-level `dead_targets` key, emitted only when non-empty. Previously only links *found on* a page could be reported, so `deadfinder file urls.txt` on a list whose entries all 404 printed `{}` and exited 0 — including the `deadfinder file <(subfinder | httpx)` workflow the README advertises. Dead targets also count toward `--coverage` and SARIF (as a distinct `DEAD_TARGET` rule).
- `<img src>`/`<img srcset>`, `<source src>`/`<source srcset>`, `<video src>`/`<video poster>`, `<audio src>`, `<track src>` and `<area href>` are extracted and checked. Broken images are among the most common dead links and were entirely invisible before: a page with ten resources had six of them checked. `srcset` is parsed per the HTML candidate grammar, so a URL containing a comma is not split apart.
- `--check-anchors` verifies that a link's `#fragment` actually exists in the linked document (`id`, or a legacy `<a name>`). `/page#does-not-exist` used to report a cheerful `200`. Opt-in, since it needs the response body; one fetch still serves every fragment pointing at the same document.
- `--target-concurrency=N` (default 10) scans several targets at once. `-c` only ever parallelized the links *within* one page, so pages were fetched strictly one after another — 20 targets behind 300 ms of latency took 6.4 s where they now take 0.9 s, and a 5000-URL sitemap paid 5000 serial round trips before any concurrency helped. `-c` becomes a *global* cap on in-flight requests rather than a per-page one, so target concurrency rides on a fixed budget instead of multiplying it into 500 sockets aimed at one host. Each target's log lines are buffered and flushed as one block so concurrent scans do not shred each other's output; with `--target-concurrency 1` the output is byte-identical to before.
- `--method=auto|head|get` (default `auto`) checks a link with HEAD and confirms with GET whenever the HEAD *status* cannot be trusted (405/501, any 4xx/5xx), so no link is ever reported dead on a HEAD status alone. A HEAD that never reached the host (connect refused/timed out, DNS failure) is not re-checked — a GET cannot succeed where the TCP connect did not, and doing so cost a second full connect timeout on every unreachable link. A status check used to download the entire body: 20 one-megabyte links cost 20 MB to learn 20 status codes, and now cost none. Documents (the target page, a sitemap) are still fetched with GET.
- Keep-alive connections are pooled per origin with borrow/return semantics, replacing a fresh `HTTP::Client` — and on HTTPS a fresh TLS handshake — for every single link check. The proxy paths are deliberately left unpooled.
- `--retry=N` (default 2) retries a *transient* failure (connection error, timeout, 429, 5xx) with jittered exponential backoff, honoring `Retry-After` in both its delta-seconds and HTTP-date forms and bounded by `--timeout`. A 404 is never retried. Only the final verdict is cached: the URL→status cache is process-global and never expires, so a single TCP reset used to mark a URL dead for every remaining page in the run.
- `--delay=MS` enforces a minimum interval between two requests to the same host, per-host so one slow host does not stall the others. A `Retry-After` earned by one worker holds back every other worker queued on that host.
- `--accept-status=LIST` and `--dead-status=LIST` (alias `--exclude-status`) override the dead/alive policy with bare codes and inclusive ranges (`200,204,403,999`, `400-499`). The rule was hardcoded at `>= 400`, which left no escape hatch for the well-known bot-defense answers — LinkedIn's `999`, Cloudflare's `403` to a non-browser User-Agent, a rate limiter's `429` — every one of them a false positive.
- Coverage output gained correctly named `dead_link_percentage` / `overall_dead_link_percentage` fields. `coverage_percentage` was always `dead / total * 100`, i.e. the dead-link ratio, so a perfectly healthy site reported "0% coverage". The old keys remain as deprecated aliases.
- Shell completions now complete subcommands, `bash|zsh|fish` after `completion`, and the output formats after `--output_format`, alongside the short flag spellings. A spec scrapes `cli.cr`'s parser and fails when any surface drifts out of step with it.
- `-k` / `--insecure`, `--limit` and `-f` / `--output_format` reached the surfaces that had never mentioned them: the README flag list, all three completion generators, `docs/`, and the Action's inputs.
- Sitemap fetching transparently inflates gzip-compressed documents, so a `sitemap.xml.gz` served as `application/gzip` (no `Content-Encoding`) is parsed instead of failing with an XML error.
- `-H`/`--headers` now applies to the sitemap request too, so a sitemap behind auth or a custom edge header can be fetched.

### Fixed
- macOS release tarballs are re-signed ad hoc after `install_name_tool` rewrites their dylib load paths. The bundled OpenSSL dylibs were left with a stale signature, and Apple Silicon SIGKILLs any process that maps one, so the tarball died at launch with a bare `killed` and no diagnostic. Packaging now verifies every signature and runs the extracted tarball before publishing it. The published 2.0.2 tarball happened to bundle no dylibs and so was unaffected (#271).

### Changed
- Scanning a page (`url`/`file`/`pipe` targets and sitemap documents) follows up to 5 redirect hops. Relative links resolve against the page's **final** location, while the report stays keyed by the target you asked for. Link status checks are unchanged — they still report the `30x` verbatim, which is what `--include30x` acts on. Credentials (`Authorization`, `Cookie`, `Proxy-Authorization`) are dropped when a redirect crosses origins.
- Multi-target scans (`pipe`/`file`/`sitemap`) now attribute a shared broken link to **every** page that references it, not just the first page scanned, and per-target coverage counts each page's own links. Internally the global "already-seen" URL set became a URL→status cache, so each link is still fetched at most once. Previously a 404 referenced by pages A and B was reported only under A and skewed B's coverage.

### Fixed
- macOS release tarballs now bundle Homebrew-linked runtime libraries (OpenSSL, libyaml, pcre2, bdw-gc) next to the binary so direct-download installs work without a local Homebrew dependency tree.
- `url`/`sitemap` no longer silently report nothing when the target redirects. Previously the `30x` body was parsed as the page (zero links discovered, no message) and a redirected sitemap failed outright with `HTTP 301`.
- Relative links are resolved against `<base href>` when the document declares one, matching browser behaviour, instead of always resolving against the page URL.
- Links that differ only by fragment (`/guide#install`, `/guide#usage`) now cost a single request — the fragment is never sent to the server — while both still appear in the report.
- A sitemap index containing relative `<loc>` entries resolves them against the parent sitemap instead of failing with "URI is missing a host".
- `--limit` stops sitemap discovery as soon as enough URLs are collected, instead of downloading every child sitemap in a sitemap index and discarding the surplus. The "Found N URLs" line now says when discovery stopped early.
- `deadfinder url example.com` (or `sitemap example.com/sitemap.xml`) fails immediately with an actionable message and a non-zero exit code instead of a cryptic `[URI is missing a host]` mid-scan.
- A target page that answers with a non-2xx status is reported, so links extracted from an error page are no longer mistaken for the real page's links. A page with no links at all now says so rather than logging nothing.
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
