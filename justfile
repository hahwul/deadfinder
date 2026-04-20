default:
    @just --list

# Install shard dependencies
deps:
    shards install

# Build a release binary at ./deadfinder
build:
    shards install
    crystal build src/cli_main.cr -o deadfinder --release --no-debug

# Build a debug binary at ./deadfinder (fast compile)
build-debug:
    shards install
    crystal build src/cli_main.cr -o deadfinder

# Run unit specs
test:
    crystal spec

# Run cross-implementation compat harness (requires built binary)
compat: build
    BIN=./deadfinder ruby spec/compat/run.rb

# Format sources
fix:
    crystal tool format src spec

# Check formatting without modifying
check-format:
    crystal tool format --check src spec

# Verify version consistency across shard.yml and src/deadfinder/version.cr
alias vc := version-check
version-check:
    crystal run scripts/version_check.cr

# Update version in all tracked files
alias vu := version-update
version-update VERSION:
    crystal run scripts/version_update.cr -- {{VERSION}}

# Clean build artifacts and dependencies
clean:
    rm -f deadfinder *.dwarf
    rm -rf lib/ .shards/
