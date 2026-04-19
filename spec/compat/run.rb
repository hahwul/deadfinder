#!/usr/bin/env ruby
# frozen_string_literal: true

# Cross-implementation compatibility harness.
#
# Runs the deadfinder binary under test against a local fixture server,
# writes the output to a temp file (deadfinder only serializes to file),
# and compares to a golden file. Golden files use the `{{BASE}}` placeholder
# for the dynamic fixture server origin.
#
# Usage:
#   ruby spec/compat/run.rb                   # uses the repo's Ruby binary
#   BIN="./crystal/deadfinder" ruby spec/compat/run.rb

require 'json'
require 'open3'
require 'tempfile'

REPO_ROOT    = File.expand_path('../..', __dir__)
HARNESS_ROOT = __dir__
DEFAULT_BIN  = "ruby -I #{REPO_ROOT}/lib #{REPO_ROOT}/bin/deadfinder"

BIN = ENV.fetch('BIN', DEFAULT_BIN)

def sort_arrays(obj)
  case obj
  when Hash  then obj.transform_values { |v| sort_arrays(v) }
  when Array then obj.map { |v| sort_arrays(v) }.sort_by(&:to_s)
  else obj
  end
end

def run_case(base, name, args, golden_path)
  Tempfile.create(['deadfinder', '.json']) do |tmp|
    cmd = "#{BIN} #{args.gsub('{{BASE}}', base)} -o #{tmp.path} -s"
    stdout, stderr, status = Open3.capture3(cmd)
    unless status.success?
      warn "FAIL: #{name} — exit #{status.exitstatus}"
      warn "CMD:     #{cmd}"
      warn "STDOUT:  #{stdout}"
      warn "STDERR:  #{stderr}"
      return false
    end

    expected = JSON.parse(File.read(golden_path).gsub('{{BASE}}', base))
    actual   = JSON.parse(File.read(tmp.path))

    if sort_arrays(actual) == sort_arrays(expected)
      puts "PASS: #{name}"
      true
    else
      warn "FAIL: #{name}"
      warn "EXPECTED: #{JSON.pretty_generate(expected)}"
      warn "ACTUAL:   #{JSON.pretty_generate(actual)}"
      false
    end
  end
end

server_io = IO.popen(['ruby', "#{HARNESS_ROOT}/fixtures/server.rb"], 'r')
port = server_io.gets&.strip
abort 'fixture server did not start' unless port && !port.empty?
base = "http://127.0.0.1:#{port}"

at_exit do
  begin
    Process.kill('TERM', server_io.pid)
  rescue Errno::ESRCH
    # already gone
  end
end

all_pass = true
all_pass &= run_case(base, 'url_json',
                     'url {{BASE}}/index.html -f json',
                     "#{HARNESS_ROOT}/golden/url_json.json")

exit(all_pass ? 0 : 1)
