require "spec"
require "webmock"
require "../src/deadfinder"
require "../src/deadfinder/cli"

def reset_deadfinder_state
  Deadfinder.output.clear
  Deadfinder.coverage_data.clear
  Deadfinder.cache_set.clear
  Deadfinder::Logger.unset_silent
  Deadfinder::Logger.unset_verbose
  Deadfinder::Logger.unset_debug
end

def default_test_options : Deadfinder::Options
  options = Deadfinder::Options.new
  options.silent = true
  options.concurrency = 2
  options
end

def make_runner_args
  {
    output:        {} of String => Array(String),
    coverage_data: {} of String => Deadfinder::TargetCoverage,
    cache_set:     {} of String => Bool,
    mutex:         Mutex.new,
  }
end
