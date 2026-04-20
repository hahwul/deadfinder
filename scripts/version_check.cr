require "yaml"

# Cross-file version consistency check. Prints each discovered version
# string and exits non-zero if they disagree.

SHARD_YML  = "shard.yml"
VERSION_CR = "src/deadfinder/version.cr"
SPEC_TOP   = "spec/deadfinder_spec.cr"
SPEC_CLI   = "spec/deadfinder/cli_spec.cr"

def shard_version : String?
  YAML.parse(File.read(SHARD_YML))["version"].as_s
rescue
  nil
end

def match_version(path : String) : String?
  content = File.read(path)
  # Matches both `VERSION = "X"` and `VERSION.should eq "X"` (with or without parens).
  m = content.match(/VERSION\s*(?:=|\.should\s+eq\(?)\s*"([^"]+)"/)
  m ? m[1] : nil
rescue
  nil
end

pairs = {
  SHARD_YML  => shard_version,
  VERSION_CR => match_version(VERSION_CR),
  SPEC_TOP   => match_version(SPEC_TOP),
  SPEC_CLI   => match_version(SPEC_CLI),
}

missing = pairs.select { |_, v| v.nil? }
unless missing.empty?
  missing.each { |path, _| STDERR.puts "version not found in #{path}" }
  exit 1
end

pairs.each { |path, v| puts "#{path}: #{v}" }

uniq = pairs.values.compact.uniq
if uniq.size == 1
  puts "OK: all files agree on #{uniq.first}"
else
  STDERR.puts "MISMATCH: #{uniq.join(", ")}"
  exit 1
end
