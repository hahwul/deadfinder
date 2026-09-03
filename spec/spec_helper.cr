require "spec"
require "webmock"
require "../src/deadfinder"
require "../src/deadfinder/cli"

def reset_deadfinder_state
  # Clears the accumulators *and* Runner's shared in-flight/permit bookkeeping,
  # which otherwise carries over between examples.
  Deadfinder.reset_state
  Deadfinder.reset_report_sink
  Deadfinder::Logger.reset_sink
  # Pooled connections and per-host throttle slots outlive a single run, so an
  # example must not inherit them from the previous one.
  Deadfinder::HttpClient.close_idle_connections
  Deadfinder::Logger.unset_silent
  Deadfinder::Logger.unset_verbose
  Deadfinder::Logger.unset_debug
end

def default_test_options : Deadfinder::Options
  options = Deadfinder::Options.new
  options.silent = true
  options.concurrency = 2
  # No retries by default in specs: a stubbed failure never becomes a success,
  # so retrying one would only add backoff sleeps. The retry behaviour has its
  # own specs in `request_layer_spec.cr`, which opt in explicitly.
  options.retries = 0
  options
end

def make_runner_args
  {
    output:        {} of String => Array(String),
    coverage_data: {} of String => Deadfinder::TargetCoverage,
    status_cache:  {} of String => Int32,
    mutex:         Mutex.new,
  }
end

# Worker jobs are `{request URL, links that resolved to it}` pairs: one request
# serves every link that differs only by fragment.
def job_for(url : String)
  {url, [url]}
end
