#!/usr/bin/env ruby
# frozen_string_literal: true

# Black-box compatibility harness for the deadfinder Crystal binary.
#
# The golden files in this directory were captured from the v1 Ruby
# implementation and now act as the frozen contract the Crystal binary
# must match. The harness runs the binary under test against a local
# fixture server, writes the output to a temp file, and compares the
# parsed structure to the corresponding golden file (with `{{BASE}}`
# substituted for the dynamic fixture origin).
#
# Usage:
#   BIN="./deadfinder" ruby spec/compat/run.rb
#   BIN="/path/to/deadfinder" ruby spec/compat/run.rb

require 'csv'
require 'json'
require 'open3'
require 'tempfile'
require 'toml-rb'
require 'yaml'

HARNESS_ROOT = __dir__

BIN = ENV.fetch('BIN', './deadfinder')

def sort_arrays(obj)
  case obj
  when Hash  then obj.transform_values { |v| sort_arrays(v) }
  when Array then obj.map { |v| sort_arrays(v) }.sort_by(&:to_s)
  else obj
  end
end

def parse_output(path, format)
  text = File.read(path)
  case format
  when 'json'        then JSON.parse(text)
  when 'yaml', 'yml' then YAML.safe_load(text)
  when 'toml'        then TomlRB.parse(text)
  when 'csv'         then CSV.parse(text)
  else raise "unknown format: #{format}"
  end
end

def substitute_base(text, base)
  text.gsub('{{BASE}}', base)
end

def run_case(base, name:, args:, format:, golden:, stdin: nil, extra_files: {})
  extra_files.each do |path, content|
    File.write(path, substitute_base(content, base))
  end

  Tempfile.create(['deadfinder', ".#{format}"]) do |tmp|
    resolved_args = substitute_base(args, base)
    cmd = "#{BIN} #{resolved_args} -o #{tmp.path} -f #{format} -s"
    stdout, stderr, status = Open3.capture3(cmd, stdin_data: stdin || '')

    unless status.success?
      warn "FAIL: #{name} — exit #{status.exitstatus}"
      warn "CMD:    #{cmd}"
      warn "STDOUT: #{stdout}"
      warn "STDERR: #{stderr}"
      return false
    end

    expected_text = substitute_base(File.read(golden), base)
    expected_path = Tempfile.new(['expected', ".#{format}"]).tap do |f|
      f.write(expected_text)
      f.close
    end.path

    expected = parse_output(expected_path, format)
    actual   = parse_output(tmp.path, format)

    if sort_arrays(actual) == sort_arrays(expected)

      true
    else
      warn "FAIL: #{name}"
      warn "EXPECTED: #{expected.inspect}"
      warn "ACTUAL:   #{actual.inspect}"
      false
    end
  end
ensure
  extra_files.each_key { |path| FileUtils.rm_f(path) }
end

# --- Boot fixture server ----------------------------------------------------
server_io = IO.popen(['ruby', "#{HARNESS_ROOT}/fixtures/server.rb"], 'r')
port = server_io.gets&.strip
abort 'fixture server did not start' unless port && !port.empty?
base = "http://127.0.0.1:#{port}"

at_exit do
  Process.kill('TERM', server_io.pid)
rescue Errno::ESRCH
  # already gone
end

# --- Cases ------------------------------------------------------------------
urls_file = File.join(Dir.tmpdir, "deadfinder_compat_urls_#{Process.pid}.txt")

results = []

results << run_case(base,
                    name: 'url_json',
                    args: 'url {{BASE}}/index.html',
                    format: 'json',
                    golden: "#{HARNESS_ROOT}/golden/url_json.json")

results << run_case(base,
                    name: 'url_yaml',
                    args: 'url {{BASE}}/index.html',
                    format: 'yaml',
                    golden: "#{HARNESS_ROOT}/golden/url_yaml.yaml")

results << run_case(base,
                    name: 'url_toml',
                    args: 'url {{BASE}}/index.html',
                    format: 'toml',
                    golden: "#{HARNESS_ROOT}/golden/url_toml.toml")

results << run_case(base,
                    name: 'url_csv',
                    args: 'url {{BASE}}/index.html',
                    format: 'csv',
                    golden: "#{HARNESS_ROOT}/golden/url_csv.csv")

results << run_case(base,
                    name: 'url_json_include30x',
                    args: 'url {{BASE}}/index.html -r',
                    format: 'json',
                    golden: "#{HARNESS_ROOT}/golden/url_json_include30x.json")

results << run_case(base,
                    name: 'file_json',
                    args: "file #{urls_file}",
                    format: 'json',
                    golden: "#{HARNESS_ROOT}/golden/file_json.json",
                    extra_files: { urls_file => "{{BASE}}/index.html\n" })

results << run_case(base,
                    name: 'pipe_json',
                    args: 'pipe',
                    format: 'json',
                    golden: "#{HARNESS_ROOT}/golden/pipe_json.json",
                    stdin: substitute_base("{{BASE}}/index.html\n", base))

exit(results.all? ? 0 : 1)
