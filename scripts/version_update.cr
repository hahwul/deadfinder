require "yaml"

# Bump the version string across every tracked file in one pass. Run:
#
#   crystal run scripts/version_update.cr -- 2.1.0
#
# or via `just version-update 2.1.0`.

SHARD_YML  = "shard.yml"
VERSION_CR = "src/deadfinder/version.cr"
SPEC_TOP   = "spec/deadfinder_spec.cr"
SPEC_CLI   = "spec/deadfinder/cli_spec.cr"

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

def replace_in_file(path : String, pattern : Regex, replacement : String) : Bool
  src = File.read(path)
  updated = src.sub(pattern, replacement)
  if updated == src
    STDERR.puts "#{path}: pattern not found"
    return false
  end
  File.write(path, updated)
  true
end

ok = true
ok &= replace_in_file(SHARD_YML, /^version:\s*.+$/m, "version: #{nv}")
puts "#{SHARD_YML}: #{nv}"

ok &= replace_in_file(VERSION_CR, /VERSION\s*=\s*"[^"]+"/, %(VERSION = "#{nv}"))
puts "#{VERSION_CR}: #{nv}"

ok &= replace_in_file(SPEC_TOP, /VERSION\.should\s+eq\s+"[^"]+"/, %(VERSION.should eq "#{nv}"))
puts "#{SPEC_TOP}: #{nv}"

ok &= replace_in_file(SPEC_CLI, /VERSION\.should\s+eq\s+"[^"]+"/, %(VERSION.should eq "#{nv}"))
puts "#{SPEC_CLI}: #{nv}"

exit(ok ? 0 : 1)
