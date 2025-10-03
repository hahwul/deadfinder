# Quick Start Guide

This is a quick reference for building and previewing the DeadFinder documentation.

## Prerequisites

Install Zola (version 0.19.2 or newer recommended):

```bash
# macOS
brew install zola

# Linux (Snap)
snap install zola

# Or download from releases
# https://github.com/getzola/zola/releases
```

## Local Development

1. **Clone with submodules:**

```bash
git clone --recursive https://github.com/hahwul/deadfinder.git
cd deadfinder/docs
```

Or if already cloned:

```bash
git submodule update --init --recursive
```

2. **Serve locally:**

```bash
cd docs
zola serve
```

Visit http://127.0.0.1:1111 in your browser.

3. **Build for production:**

```bash
cd docs
zola build
```

Output will be in the `docs/public/` directory.

## Structure

```
docs/
├── config.toml              # Site configuration
├── content/                 # Markdown content
│   ├── _index.md            # Landing page
│   ├── get_started/         # Installation, usage, options
│   ├── integration/         # GitHub Action, Ruby API
│   └── contributing/        # Contributing guide
├── static/                  # Static assets
│   └── images/              # Images (logo, preview, etc.)
└── themes/goyo/             # Goyo theme (submodule)
```

## Adding Content

### New Page

1. Create directory and file:
```bash
mkdir -p content/section/page_name
touch content/section/page_name/index.md
```

2. Add front matter:
```markdown
---
title: "Page Title"
weight: 1
---

Content here...
```

### Section Index

```markdown
+++
title = "Section Name"
weight = 1
sort_by = "weight"

[extra]
+++
```

## Deploying

See `deploy-docs.yml.example` for GitHub Actions workflow example.

For manual deployment:

```bash
cd docs
zola build
# Copy public/ to your web server
```

## Troubleshooting

### Submodule not initialized

```bash
git submodule update --init --recursive
```

### Build errors

Make sure you're using Zola 0.19.2 or newer:

```bash
zola --version
```

### Preview not updating

Clear the cache and rebuild:

```bash
rm -rf public .zola-cache
zola serve
```

## Resources

- [Zola Documentation](https://www.getzola.org/documentation/)
- [Goyo Theme](https://github.com/hahwul/goyo)
- [Full Documentation README](README.md)
