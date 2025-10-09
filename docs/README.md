# DeadFinder Documentation

This directory contains the source for the DeadFinder documentation website, built with [Zola](https://www.getzola.org/) and the [Goyo](https://github.com/hahwul/goyo) theme.

## Structure

```
docs/
├── config.toml           # Zola configuration
├── content/              # Markdown content files
│   ├── _index.md         # Landing page
│   ├── get_started/      # Getting started guides
│   │   ├── _index.md
│   │   ├── installation/
│   │   ├── usage/
│   │   └── options/
│   ├── integration/      # Integration guides
│   │   ├── _index.md
│   │   ├── github_action/
│   │   └── ruby_api/
│   └── contributing/     # Contributing guide
│       └── _index.md
├── static/               # Static assets (images, favicon, etc.)
│   ├── images/
│   └── README.md
└── themes/
    └── goyo/             # Goyo theme (git submodule)
```

## Building the Documentation

### Prerequisites

Install Zola from https://www.getzola.org/documentation/getting-started/installation/

Or using package managers:

```bash
# macOS
brew install zola

# Linux (Snap)
snap install zola

# Windows (Scoop)
scoop install zola

# Or download from GitHub releases
# https://github.com/getzola/zola/releases
```

### Local Development

1. Clone the repository with submodules:

```bash
git clone --recursive https://github.com/hahwul/deadfinder.git
cd deadfinder/docs
```

If you already cloned without `--recursive`:

```bash
git submodule update --init --recursive
```

2. Serve the documentation locally:

```bash
zola serve
```

The site will be available at http://127.0.0.1:1111

Zola will automatically reload when you make changes to content files.

3. Build for production:

```bash
zola build
```

The generated site will be in the `public/` directory.

## Content Structure

### Front Matter

Each page uses TOML front matter:

```toml
---
title: "Page Title"
weight: 1  # Order in navigation
---
```

Landing pages use extended front matter:

```toml
+++
template = "landing.html"

[extra.hero]
title = "Welcome!"
badge = "v1.9.1"
description = "..."
# ...
+++
```

### Sections

Sections are directories with an `_index.md` file:

```toml
+++
title = "Section Name"
weight = 1
sort_by = "weight"

[extra]
+++
```

### Pages

Regular pages are markdown files in subdirectories:

```toml
---
title: "Page Title"
weight: 1
---

# Content here
```

## Theme Configuration

The Goyo theme is configured in `config.toml`:

```toml
theme = "goyo"

[extra]
logo_text = "DeadFinder"
logo_image_path = "images/logo.png"
# ...

nav = [
    { name = "Documents", url = "/get_started/installation", type = "url", icon = "fa-solid fa-book" },
    # ...
]
```

## Adding Content

### New Section

1. Create directory: `content/new_section/`
2. Create `_index.md`:

```toml
+++
title = "New Section"
weight = 4
sort_by = "weight"

[extra]
+++
```

3. Add pages in subdirectories

### New Page

1. Create directory: `content/section/new_page/`
2. Create `index.md`:

```markdown
---
title: "New Page"
weight: 1
---

Content here...
```

## Static Assets

Place images and other assets in `static/`:

- `static/images/logo.png` - Logo
- `static/images/preview.jpg` - Preview image
- `static/favicon.ico` - Favicon

Reference in content:

```markdown
![Alt text](/images/logo.png)
```

## Deployment

### GitHub Pages

The site can be deployed to GitHub Pages using GitHub Actions.

Example workflow (`.github/workflows/deploy-docs.yml`):

```yaml
name: Deploy Documentation

on:
  push:
    branches: [main]
    paths:
      - 'docs/**'

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: true
      
      - name: Install Zola
        run: |
          wget https://github.com/getzola/zola/releases/download/v0.18.0/zola-v0.18.0-x86_64-unknown-linux-gnu.tar.gz
          tar xzf zola-v0.18.0-x86_64-unknown-linux-gnu.tar.gz
          sudo mv zola /usr/local/bin/
      
      - name: Build
        run: cd docs && zola build
      
      - name: Deploy
        uses: peaceiris/actions-gh-pages@v3
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          publish_dir: ./docs/public
```

### Custom Domain

1. Add CNAME file to `static/`:

```bash
echo "deadfinder.hahwul.com" > static/CNAME
```

2. Update `base_url` in `config.toml`:

```toml
base_url = "https://deadfinder.hahwul.com"
```

## References

- [Zola Documentation](https://www.getzola.org/documentation/)
- [Goyo Theme](https://github.com/hahwul/goyo)
- [Goyo Theme Demo](https://goyo.hahwul.com)
- [DeadFinder Repository](https://github.com/hahwul/deadfinder)

## Contributing

To contribute to the documentation:

1. Fork the repository
2. Create a branch
3. Make your changes
4. Test locally with `zola serve`
5. Submit a pull request

For content guidelines, see [Contributing Guide](content/contributing/_index.md).
