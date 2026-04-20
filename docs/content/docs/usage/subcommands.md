+++
title = "Subcommands"
description = "url / file / pipe / sitemap / completion / version"
weight = 1
+++

## `url <URL>`

Scan a single page. Extract links from the HTML and check each one.

```bash
deadfinder url https://www.example.com
```

## `file <FILE>`

Read newline-separated URLs from a file and scan each one. Each URL is scanned independently; results are keyed by the source URL.

```bash
deadfinder file urls.txt
```

## `pipe`

Read URLs from STDIN (one per line). Useful in shell pipelines.

```bash
grep '^https://' access.log | sort -u | deadfinder pipe
```

## `sitemap <SITEMAP-URL>`

Parse an XML sitemap, follow sitemap indexes recursively, and scan every `<loc>`.

```bash
deadfinder sitemap https://www.example.com/sitemap.xml
```

## `completion <SHELL>`

Emit shell completion for bash, zsh, or fish.

```bash
# Bash
deadfinder completion bash > /etc/bash_completion.d/deadfinder

# Zsh
deadfinder completion zsh > ~/.zsh/completion/_deadfinder

# Fish
deadfinder completion fish > ~/.config/fish/completions/deadfinder.fish
```

## `version`

Print the DeadFinder version.

```bash
deadfinder version
```
