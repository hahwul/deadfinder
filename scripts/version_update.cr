require "yaml"

# Bump the version string across every tracked file in one pass. Run:
#
#   crystal run scripts/version_update.cr -- 2.1.0
#
# or via `just version-update 2.1.0`.

SHARD_YML  = "shard.yml"
VERSION_CR = "src/deadfinder/version.cr"

SEMVER = /\A\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?\z/

def usage(code = 1)
  STDERR.puts "usage: crystal run scripts/version_update.cr -- <NEW_VERSION>"
  exit code
end

new_version = ARGV[0]?
usage unless new_version
unless new_version.as(String).matches?(SEMVER)
  STDERR.puts "invalid semver: #{new_version}"
  usage
end

nv = new_version.as(String)

# shard.yml: replace top-level `version: ...`
shard_src = File.read(SHARD_YML)
updated_shard = shard_src.sub(/^version:\s*.+$/m, "version: #{nv}")
if updated_shard == shard_src
  STDERR.puts "#{SHARD_YML}: no version: line found"
  exit 1
end
File.write(SHARD_YML, updated_shard)
puts "#{SHARD_YML}: #{nv}"

# src/deadfinder/version.cr: replace VERSION = "..."
vcr_src = File.read(VERSION_CR)
updated_vcr = vcr_src.sub(/VERSION\s*=\s*"[^"]+"/, %(VERSION = "#{nv}"))
if updated_vcr == vcr_src
  STDERR.puts "#{VERSION_CR}: no VERSION constant found"
  exit 1
end
File.write(VERSION_CR, updated_vcr)
puts "#{VERSION_CR}: #{nv}"

puts "done"
