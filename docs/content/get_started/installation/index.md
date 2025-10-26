---
title: "Installation"
weight: 1
---

DeadFinder can be installed in several ways, depending on your preference and environment.

## Install with Gem

### CLI

```bash
gem install deadfinder
# https://rubygems.org/gems/deadfinder
```

### Gemfile

If you want to use DeadFinder in your Ruby project, add this to your `Gemfile`:

```ruby
gem 'deadfinder'
# and `bundle install`
```

## Install with Homebrew

For macOS and Linux users, DeadFinder is available via Homebrew:

```bash
brew install deadfinder
# https://formulae.brew.sh/formula/deadfinder
```

## Docker Image

DeadFinder is also available as a Docker image on GitHub Container Registry:

```bash
docker pull ghcr.io/hahwul/deadfinder:latest
```

Run DeadFinder using Docker:

```bash
docker run ghcr.io/hahwul/deadfinder:latest deadfinder --help
```

## From Source

To build DeadFinder from source, you'll need Ruby 3.4+ installed:

```bash
git clone https://github.com/hahwul/deadfinder.git
cd deadfinder
bundle install
bundle exec ruby -I lib bin/deadfinder --help
```

## Verification

After installation, verify that DeadFinder is installed correctly:

```bash
deadfinder version
```

You should see the version information displayed.
