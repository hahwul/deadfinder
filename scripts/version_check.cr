require "yaml"

# Cross-file version consistency check. Prints each discovered version
# string and exits non-zero if any tracked file disagrees (files that
# don't exist yet are skipped silently so the script works on branches
# that haven't landed the snap/aur packaging yet).

SHARD_YML  = "shard.yml"
VERSION_CR = "src/deadfinder/version.cr"
SPEC_TOP   = "spec/deadfinder_spec.cr"
SPEC_CLI   = "spec/deadfinder/cli_spec.cr"
SNAPCRAFT  = "snap/snapcraft.yaml"
PKGBUILD   = "aur/PKGBUILD"

def shard_version(path : String) : String?
  YAML.parse(File.read(path))["version"].as_s
rescue
  nil
end

def match_pattern(path : String, pattern : Regex) : String?
  content = File.read(path)
  m = content.match(pattern)
  m ? m[1] : nil
rescue
  nil
end

# Matches both `VERSION = "X"` and `VERSION.should eq "X"` (with or without parens).
CR_VERSION_RE = /VERSION\s*(?:=|\.should\s+eq\(?)\s*"([^"]+)"/
# PKGBUILD: pkgver=X.Y.Z
PKGBUILD_RE = /^pkgver=([^\s]+)/m

results = [] of {String, String}

results << {SHARD_YML, shard_version(SHARD_YML).not_nil!} if File.exists?(SHARD_YML)
results << {VERSION_CR, match_pattern(VERSION_CR, CR_VERSION_RE).not_nil!} if File.exists?(VERSION_CR)
results << {SPEC_TOP, match_pattern(SPEC_TOP, CR_VERSION_RE).not_nil!} if File.exists?(SPEC_TOP)
results << {SPEC_CLI, match_pattern(SPEC_CLI, CR_VERSION_RE).not_nil!} if File.exists?(SPEC_CLI)
results << {SNAPCRAFT, shard_version(SNAPCRAFT).not_nil!} if File.exists?(SNAPCRAFT)
results << {PKGBUILD, match_pattern(PKGBUILD, PKGBUILD_RE).not_nil!} if File.exists?(PKGBUILD)

if results.empty?
  STDERR.puts "no tracked version files found"
  exit 1
end

results.each { |path, v| puts "#{path}: #{v}" }

uniq = results.map { |_, v| v }.uniq
if uniq.size == 1
  puts "OK: all files agree on #{uniq.first}"
else
  STDERR.puts "MISMATCH: #{uniq.join(", ")}"
  exit 1
end
