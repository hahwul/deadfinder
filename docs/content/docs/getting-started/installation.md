+++
title = "Installation"
description = "Install DeadFinder via Homebrew, Docker, prebuilt binary, Nix, or from source."
weight = 1
+++

Pick the channel that fits your environment. All paths produce the same CLI.

## Homebrew (macOS / Linux)

```bash
brew install deadfinder
```

## Docker

Image: [`ghcr.io/hahwul/deadfinder`](https://github.com/hahwul/deadfinder/pkgs/container/deadfinder). Multi-arch (linux/amd64, linux/arm64). Each published tag is cosign-signed.

```bash
docker run ghcr.io/hahwul/deadfinder:latest deadfinder url https://example.com
```

## Prebuilt binary

Download the tarball for your platform from [Releases](https://github.com/hahwul/deadfinder/releases/latest) (a `.sha256` sidecar ships alongside each tarball):

| OS | Arch | Asset |
|---|---|---|
| Linux | x86_64 | `deadfinder-linux-x86_64.tar.gz` |
| Linux | aarch64 | `deadfinder-linux-aarch64.tar.gz` |
| macOS | arm64 | `deadfinder-macos-arm64.tar.gz` |

> Intel macOS (`x86_64`) doesn't have a prebuilt binary — use `brew install deadfinder` (builds from source) or run the Apple Silicon binary under Rosetta.

Extract and put `deadfinder` on your `PATH`:

```bash
curl -fsSL https://github.com/hahwul/deadfinder/releases/latest/download/deadfinder-linux-x86_64.tar.gz \
  | tar xz
sudo mv deadfinder /usr/local/bin/
```

## Linux package managers

| Distro | Package |
|---|---|
| Debian / Ubuntu | `deadfinder_X.Y.Z_{amd64,arm64}.deb` from Releases |
| RHEL / Fedora | `deadfinder-X.Y.Z.{x86_64,aarch64}.rpm` from Releases |
| Alpine | `deadfinder-X.Y.Z-r0.{x86_64,aarch64}.apk` from Releases |
| Arch Linux | `yay -S deadfinder` (AUR) |
| Snap | `sudo snap install deadfinder` |

## Nix

```bash
nix run github:hahwul/deadfinder
nix profile install github:hahwul/deadfinder
nix develop github:hahwul/deadfinder
```

## Build from source

Prerequisites:

- Crystal >= 1.19.1
- `cmake` — required by the `lexbor` HTML parser's postinstall step. Without it, `shards install` fails with `Error executing process: 'cmake': No such file or directory`.

```bash
# macOS
brew install crystal cmake

# Debian / Ubuntu
sudo apt install crystal cmake

# Arch Linux
sudo pacman -S crystal cmake
```

Then build:

```bash
git clone https://github.com/hahwul/deadfinder
cd deadfinder
shards install
crystal build src/cli_main.cr -o deadfinder --release --no-debug
```

Or use the [`justfile`](https://github.com/hahwul/deadfinder/blob/main/justfile) recipes:

```bash
just build        # release binary
just build-debug  # fast debug build
just test         # run specs
```
