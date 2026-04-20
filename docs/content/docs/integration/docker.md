+++
title = "Docker"
description = "ghcr.io/hahwul/deadfinder — multi-arch, cosign-signed, tiny Alpine base."
weight = 2
+++

# Docker

Image: [`ghcr.io/hahwul/deadfinder`](https://github.com/hahwul/deadfinder/pkgs/container/deadfinder)

- Multi-arch: `linux/amd64`, `linux/arm64`
- Runtime base: `alpine:3.21` + static binary (~15 MB total)
- Tags on release: `<VERSION>`, `<MAJOR>.<MINOR>`, `latest`
- Every published tag is **cosign-signed** (keyless, Sigstore)

## Run

The image's `CMD` is `["deadfinder"]`. Append arguments after the image name — `docker run` passes them through:

```bash
docker run ghcr.io/hahwul/deadfinder:latest deadfinder url https://www.example.com
docker run ghcr.io/hahwul/deadfinder:latest deadfinder sitemap https://www.example.com/sitemap.xml
```

Writing results out? Bind-mount a host directory:

```bash
docker run --rm -v "$PWD":/out \
  ghcr.io/hahwul/deadfinder:latest \
  deadfinder url https://www.example.com -o /out/results.json -s
```

## Pin a version

```bash
docker pull ghcr.io/hahwul/deadfinder:2.0.0
docker pull ghcr.io/hahwul/deadfinder:2.0
docker pull ghcr.io/hahwul/deadfinder:latest
```

## Verify the signature

```bash
cosign verify ghcr.io/hahwul/deadfinder:2.0.0 \
  --certificate-identity-regexp 'https://github.com/hahwul/deadfinder/.+' \
  --certificate-oidc-issuer 'https://token.actions.githubusercontent.com'
```

Substitute the tag you pulled. The command succeeds only if the image was signed by this repo's GitHub Actions.
