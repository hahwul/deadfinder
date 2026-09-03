require "../spec_helper"

# Specs for the request layer: how a single link check is performed
# (`--method`), how connections are reused, how transient failures are retried
# and throttled, and how the dead/alive verdict is decided. Kept in its own file
# so it does not collide with the link-extraction specs in `runner_spec.cr`.

# Runs one link with a given status through the full pipeline and reports
# whether it ended up flagged as dead.
def link_flagged?(status : Int32, options : Deadfinder::Options) : Bool
  # Reset first: an example that calls this more than once would otherwise leave
  # the previous status registered, and WebMock answers with the first match.
  WebMock.reset
  target = "http://example.com"
  html = %(<html><body><a href="http://example.com/link">L</a></body></html>)
  WebMock.stub(:get, target).to_return(body: html)
  WebMock.stub(:get, "http://example.com/link").to_return(status: status)

  args = make_runner_args
  Deadfinder::Runner.new.run(target, options, **args)
  (args[:output][target]? || [] of String).includes?("http://example.com/link")
end

# Options for a policy spec: one GET, no retries, so the only variable under
# test is the dead/alive decision.
def policy_options : Deadfinder::Options
  options = default_test_options
  options.http_method = "get"
  options.retries = 0
  options
end

describe "request layer" do
  before_each do
    WebMock.reset
    reset_deadfinder_state
  end

  describe Deadfinder::StatusList do
    it "parses a comma-separated list of single codes" do
      Deadfinder::StatusList.parse("200,204,403,999").should eq [200..200, 204..204, 403..403, 999..999]
    end

    it "parses inclusive ranges and tolerates surrounding whitespace" do
      Deadfinder::StatusList.parse(" 400-499 , 503 ").should eq [400..499, 503..503]
    end

    it "returns an empty list for an empty or blank value" do
      Deadfinder::StatusList.parse("").should be_empty
      Deadfinder::StatusList.parse(" , ").should be_empty
    end

    it "rejects a non-numeric entry" do
      expect_raises(ArgumentError, /invalid status code/) do
        Deadfinder::StatusList.parse("200,abc")
      end
    end

    it "rejects an inverted range" do
      expect_raises(ArgumentError, /greater than/) do
        Deadfinder::StatusList.parse("499-400")
      end
    end

    it "matches codes against parsed ranges" do
      ranges = Deadfinder::StatusList.parse("403,500-599")
      Deadfinder::StatusList.includes?(ranges, 403).should be_true
      Deadfinder::StatusList.includes?(ranges, 503).should be_true
      Deadfinder::StatusList.includes?(ranges, 404).should be_false
      Deadfinder::StatusList.includes?([] of Range(Int32, Int32), 404).should be_false
    end
  end

  describe "Options defaults for the request layer" do
    it "defaults to auto method, a small retry budget and no delay" do
      options = Deadfinder::Options.new
      options.http_method.should eq "auto"
      options.retries.should eq 2
      options.delay.should eq 0
      options.accept_status.should eq ""
      options.accept_status_ranges.should be_empty
      options.dead_status.should eq ""
      options.dead_status_ranges.should be_empty
    end

    it "parses status lists as they are assigned" do
      options = Deadfinder::Options.new
      options.accept_status = "403,999"
      options.dead_status = "500-599"
      options.accept_status_ranges.should eq [403..403, 999..999]
      options.dead_status_ranges.should eq [500..599]
    end
  end

  describe Deadfinder::HttpClient do
    describe ".parse_retry_after" do
      it "reads the delta-seconds form" do
        Deadfinder::HttpClient.parse_retry_after("120").should eq 120.seconds
      end

      it "reads the HTTP-date form as a span from now" do
        future = (Time.utc + 90.seconds).to_s("%a, %d %b %Y %H:%M:%S GMT")
        span = Deadfinder::HttpClient.parse_retry_after(future)
        span.should_not be_nil
        span.not_nil!.total_seconds.should be_close(90, 5)
      end

      it "clamps a date already in the past to zero" do
        past = (Time.utc - 1.hour).to_s("%a, %d %b %Y %H:%M:%S GMT")
        Deadfinder::HttpClient.parse_retry_after(past).should eq Time::Span.zero
      end

      it "clamps a negative delta to zero" do
        Deadfinder::HttpClient.parse_retry_after("-5").should eq Time::Span.zero
      end

      it "returns nil for an absent or unparseable value" do
        Deadfinder::HttpClient.parse_retry_after(nil).should be_nil
        Deadfinder::HttpClient.parse_retry_after("   ").should be_nil
        Deadfinder::HttpClient.parse_retry_after("soon").should be_nil
      end
    end

    describe ".origin_key" do
      it "folds the default port into the key so both spellings share a connection" do
        Deadfinder::HttpClient.origin_key(URI.parse("https://example.com/a"))
          .should eq Deadfinder::HttpClient.origin_key(URI.parse("https://example.com:443/b"))
      end

      it "separates hosts, ports and schemes" do
        a = Deadfinder::HttpClient.origin_key(URI.parse("http://example.com/"))
        b = Deadfinder::HttpClient.origin_key(URI.parse("http://example.com:8080/"))
        c = Deadfinder::HttpClient.origin_key(URI.parse("https://example.com/"))
        d = Deadfinder::HttpClient.origin_key(URI.parse("http://other.com/"))
        [a, b, c, d].uniq.size.should eq 4
      end
    end

    describe ".check" do
      it "uses HEAD alone when the server answers it happily" do
        # No GET stub: WebMock raises on any unstubbed request, so this fails
        # loudly if a GET is issued.
        WebMock.stub(:head, "http://example.com/ok").to_return(status: 200)

        options = default_test_options
        response = Deadfinder::HttpClient.check(URI.parse("http://example.com/ok"), options, HTTP::Headers.new)
        response.status_code.should eq 200
      end

      it "confirms a 405 with a GET rather than reporting it" do
        WebMock.stub(:head, "http://example.com/nohead").to_return(status: 405)
        WebMock.stub(:get, "http://example.com/nohead").to_return(status: 200)

        options = default_test_options
        Deadfinder::HttpClient.check(URI.parse("http://example.com/nohead"), options, HTTP::Headers.new)
          .status_code.should eq 200
      end

      it "confirms a 501 with a GET" do
        WebMock.stub(:head, "http://example.com/x").to_return(status: 501)
        WebMock.stub(:get, "http://example.com/x").to_return(status: 200)

        options = default_test_options
        Deadfinder::HttpClient.check(URI.parse("http://example.com/x"), options, HTTP::Headers.new)
          .status_code.should eq 200
      end

      it "confirms any 4xx/5xx with a GET, so a CDN's HEAD-only 403 is not a dead link" do
        WebMock.stub(:head, "http://example.com/cdn").to_return(status: 403)
        WebMock.stub(:get, "http://example.com/cdn").to_return(status: 200)

        options = default_test_options
        Deadfinder::HttpClient.check(URI.parse("http://example.com/cdn"), options, HTTP::Headers.new)
          .status_code.should eq 200
      end

      it "falls back to GET when the HEAD itself fails at the transport level" do
        # Only GET is stubbed, so the HEAD raises inside `check`.
        WebMock.stub(:get, "http://example.com/reset").to_return(status: 200)

        options = default_test_options
        Deadfinder::HttpClient.check(URI.parse("http://example.com/reset"), options, HTTP::Headers.new)
          .status_code.should eq 200
      end

      it "reports the GET status when the GET agrees the link is dead" do
        WebMock.stub(:head, "http://example.com/gone").to_return(status: 404)
        WebMock.stub(:get, "http://example.com/gone").to_return(status: 404)

        options = default_test_options
        Deadfinder::HttpClient.check(URI.parse("http://example.com/gone"), options, HTTP::Headers.new)
          .status_code.should eq 404
      end

      it "keeps a redirect from HEAD verbatim, without following or re-checking it" do
        WebMock.stub(:head, "http://example.com/moved")
          .to_return(status: 301, headers: HTTP::Headers{"Location" => "http://example.com/ok"})

        options = default_test_options
        Deadfinder::HttpClient.check(URI.parse("http://example.com/moved"), options, HTTP::Headers.new)
          .status_code.should eq 301
      end

      it "skips the HEAD probe when the caller already knows the URL failed" do
        # Only GET is stubbed: a HEAD would raise, which is the point — force_get
        # must not send one.
        WebMock.stub(:get, "http://example.com/retry").to_return(status: 200)

        options = default_test_options
        Deadfinder::HttpClient.check(URI.parse("http://example.com/retry"), options, HTTP::Headers.new, true)
          .status_code.should eq 200
      end

      it "sends only HEAD under --method=head, taking the server at its word" do
        WebMock.stub(:head, "http://example.com/nohead").to_return(status: 405)

        options = default_test_options
        options.http_method = "head"
        Deadfinder::HttpClient.check(URI.parse("http://example.com/nohead"), options, HTTP::Headers.new)
          .status_code.should eq 405
      end

      it "sends only GET under --method=get" do
        WebMock.stub(:get, "http://example.com/only-get").to_return(status: 200)

        options = default_test_options
        options.http_method = "get"
        Deadfinder::HttpClient.check(URI.parse("http://example.com/only-get"), options, HTTP::Headers.new)
          .status_code.should eq 200
      end
    end

    describe Deadfinder::HttpClient::ConnectionPool do
      it "hands a checked-in client back out again" do
        pool = Deadfinder::HttpClient::ConnectionPool.new
        client = HTTP::Client.new("example.com")
        pool.checkin("k", client)
        pool.checkout("k").should be client
      ensure
        pool.try &.close_all
      end

      it "never hands the same client to two borrowers" do
        pool = Deadfinder::HttpClient::ConnectionPool.new
        pool.checkin("k", HTTP::Client.new("example.com"))

        first = pool.checkout("k")
        second = pool.checkout("k")

        first.should_not be_nil
        second.should be_nil
        pool.idle_count("k").should eq 0
      ensure
        pool.try &.close_all
      end

      it "keys clients by origin" do
        pool = Deadfinder::HttpClient::ConnectionPool.new
        pool.checkin("a", HTTP::Client.new("a.example.com"))
        pool.checkout("b").should be_nil
        pool.checkout("a").should_not be_nil
      ensure
        pool.try &.close_all
      end

      it "bounds the number of idle clients per origin" do
        pool = Deadfinder::HttpClient::ConnectionPool.new
        cap = Deadfinder::HttpClient::ConnectionPool::MAX_IDLE_PER_ORIGIN
        (cap + 3).times { pool.checkin("k", HTTP::Client.new("example.com")) }
        pool.idle_count("k").should eq Math.min(cap, Deadfinder::HttpClient::ConnectionPool::MAX_IDLE_TOTAL)
      ensure
        pool.try &.close_all
      end

      it "bounds the total number of idle clients across origins" do
        pool = Deadfinder::HttpClient::ConnectionPool.new
        cap = Deadfinder::HttpClient::ConnectionPool::MAX_IDLE_TOTAL
        # One connection each to far more hosts than the global cap allows: a
        # scan whose links fan out over many hosts must not accumulate an
        # unbounded number of open file descriptors.
        (cap + 20).times { |i| pool.checkin("host#{i}", HTTP::Client.new("h#{i}.example.com")) }
        pool.total_idle.should eq cap
      ensure
        pool.try &.close_all
      end

      it "evicts the least recently used origin first" do
        pool = Deadfinder::HttpClient::ConnectionPool.new
        cap = Deadfinder::HttpClient::ConnectionPool::MAX_IDLE_TOTAL
        cap.times { |i| pool.checkin("old#{i}", HTTP::Client.new("h#{i}.example.com")) }
        pool.checkin("fresh", HTTP::Client.new("fresh.example.com"))

        # The newest check-in survives; the first (oldest) origin is the one dropped.
        pool.idle_count("fresh").should eq 1
        pool.idle_count("old0").should eq 0
        pool.total_idle.should eq cap
      ensure
        pool.try &.close_all
      end

      it "forgets an origin once its last connection is taken" do
        pool = Deadfinder::HttpClient::ConnectionPool.new
        pool.checkin("k", HTTP::Client.new("example.com"))
        pool.checkout("k").should_not be_nil
        pool.total_idle.should eq 0
        pool.idle_count("k").should eq 0
      ensure
        pool.try &.close_all
      end

      it "does not keep a discarded client" do
        pool = Deadfinder::HttpClient::ConnectionPool.new
        pool.discard(HTTP::Client.new("example.com"))
        pool.idle_count("k").should eq 0
        pool.checkout("k").should be_nil
      ensure
        pool.try &.close_all
      end

      it "drops everything on close_all" do
        pool = Deadfinder::HttpClient::ConnectionPool.new
        pool.checkin("k", HTTP::Client.new("example.com"))
        pool.close_all
        pool.checkout("k").should be_nil
      end
    end

    describe Deadfinder::HttpClient::HostThrottle do
      it "does not wait when no delay is configured" do
        throttle = Deadfinder::HttpClient::HostThrottle.new
        started = Time.measure do
          5.times { throttle.acquire("h", Time::Span.zero) }
        end
        started.should be < 50.milliseconds
      end

      it "spaces consecutive requests to the same host" do
        throttle = Deadfinder::HttpClient::HostThrottle.new
        elapsed = Time.measure do
          3.times { throttle.acquire("h", 40.milliseconds) }
        end
        # First call takes its slot immediately; the next two wait one interval each.
        elapsed.should be >= 70.milliseconds
      end

      it "throttles per host, so a slow host does not stall the others" do
        throttle = Deadfinder::HttpClient::HostThrottle.new
        throttle.acquire("slow", 500.milliseconds)
        elapsed = Time.measure { throttle.acquire("fast", 500.milliseconds) }
        elapsed.should be < 100.milliseconds
      end

      it "holds a whole host back after a penalty" do
        throttle = Deadfinder::HttpClient::HostThrottle.new
        throttle.penalize("h", 80.milliseconds)
        elapsed = Time.measure { throttle.acquire("h", 1.millisecond) }
        elapsed.should be >= 50.milliseconds
      end

      it "applies a penalty even when no --delay is configured" do
        throttle = Deadfinder::HttpClient::HostThrottle.new
        throttle.penalize("h", 80.milliseconds)
        elapsed = Time.measure { throttle.acquire("h", Time::Span.zero) }
        elapsed.should be >= 50.milliseconds
        # Only the penalized host is held back.
        Time.measure { throttle.acquire("other", Time::Span.zero) }.should be < 50.milliseconds
      end

      it "ignores a non-positive penalty" do
        throttle = Deadfinder::HttpClient::HostThrottle.new
        throttle.penalize("h", Time::Span.zero)
        elapsed = Time.measure { throttle.acquire("h", 1.millisecond) }
        elapsed.should be < 50.milliseconds
      end
    end
  end

  describe "retrying transient failures" do
    it "retries a 5xx and caches the eventual success, not the transient failure" do
      target = "http://example.com"
      html = %(<html><body><a href="http://example.com/flaky">F</a></body></html>)
      WebMock.stub(:get, target).to_return(body: html)

      calls = 0
      WebMock.stub(:get, "http://example.com/flaky").to_return do |_request|
        calls += 1
        HTTP::Client::Response.new(calls == 1 ? 500 : 200, body: "", headers: HTTP::Headers{"Content-length" => "0"})
      end

      options = default_test_options
      options.http_method = "get"
      options.retries = 2
      args = make_runner_args

      Deadfinder::Runner.new.run(target, options, **args)

      calls.should eq 2
      (args[:output][target]? || [] of String).should_not contain "http://example.com/flaky"
      args[:status_cache]["http://example.com/flaky"].should eq 200
    end

    it "retries a 429" do
      target = "http://example.com"
      html = %(<html><body><a href="http://example.com/limited">L</a></body></html>)
      WebMock.stub(:get, target).to_return(body: html)

      calls = 0
      WebMock.stub(:get, "http://example.com/limited").to_return do |_request|
        calls += 1
        HTTP::Client::Response.new(calls == 1 ? 429 : 200, body: "", headers: HTTP::Headers{"Content-length" => "0"})
      end

      options = default_test_options
      options.http_method = "get"
      options.retries = 1
      args = make_runner_args

      Deadfinder::Runner.new.run(target, options, **args)

      calls.should eq 2
      (args[:output][target]? || [] of String).should_not contain "http://example.com/limited"
    end

    it "retries a connection failure and reports it dead only after the budget is spent" do
      target = "http://example.com"
      html = %(<html><body><a href="http://example.com/down">D</a></body></html>)
      WebMock.stub(:get, target).to_return(body: html)
      # No stub for /down at all, so every attempt raises.

      options = default_test_options
      options.http_method = "get"
      options.retries = 1
      args = make_runner_args

      Deadfinder::Runner.new.run(target, options, **args)

      args[:output][target].should contain "http://example.com/down"
      args[:status_cache]["http://example.com/down"].should eq Deadfinder::Runner::ERROR_STATUS
    end

    it "stops re-probing with HEAD once an attempt has failed outright" do
      target = "http://example.com"
      html = %(<html><body><a href="http://example.com/blackhole">B</a></body></html>)
      WebMock.stub(:get, target).to_return(body: html)

      head_calls = 0
      WebMock.stub(:head, "http://example.com/blackhole").to_return do |_request|
        head_calls += 1
        HTTP::Client::Response.new(503, body: "", headers: HTTP::Headers{"Content-length" => "0"})
      end
      # No GET stub for the link, so the confirming GET raises on every attempt.

      options = default_test_options
      options.retries = 2
      args = make_runner_args

      Deadfinder::Runner.new.run(target, options, **args)

      # Attempt 1 probes with HEAD and then fails on the GET; attempts 2 and 3
      # go straight to GET rather than paying for the HEAD again.
      head_calls.should eq 1
      args[:status_cache]["http://example.com/blackhole"].should eq Deadfinder::Runner::ERROR_STATUS
    end

    it "never retries a 404 - a dead link still costs a single check" do
      target = "http://example.com"
      html = %(<html><body><a href="http://example.com/gone">G</a></body></html>)
      WebMock.stub(:get, target).to_return(body: html)

      calls = 0
      WebMock.stub(:get, "http://example.com/gone").to_return do |_request|
        calls += 1
        HTTP::Client::Response.new(404, body: "", headers: HTTP::Headers{"Content-length" => "0"})
      end

      options = default_test_options
      options.http_method = "get"
      options.retries = 3
      args = make_runner_args

      Deadfinder::Runner.new.run(target, options, **args)

      calls.should eq 1
      args[:output][target].should contain "http://example.com/gone"
    end

    it "performs exactly one attempt when --retry is 0" do
      target = "http://example.com"
      html = %(<html><body><a href="http://example.com/err">E</a></body></html>)
      WebMock.stub(:get, target).to_return(body: html)

      calls = 0
      WebMock.stub(:get, "http://example.com/err").to_return do |_request|
        calls += 1
        HTTP::Client::Response.new(500, body: "", headers: HTTP::Headers{"Content-length" => "0"})
      end

      options = default_test_options
      options.http_method = "get"
      options.retries = 0
      args = make_runner_args

      Deadfinder::Runner.new.run(target, options, **args)

      calls.should eq 1
    end

    it "bounds an outsized Retry-After by --timeout so a hostile header cannot hang the run" do
      target = "http://example.com"
      html = %(<html><body><a href="http://example.com/hostile">H</a></body></html>)
      WebMock.stub(:get, target).to_return(body: html)

      calls = 0
      WebMock.stub(:get, "http://example.com/hostile").to_return do |_request|
        calls += 1
        if calls == 1
          HTTP::Client::Response.new(429, body: "",
            headers: HTTP::Headers{"Content-length" => "0", "Retry-After" => "86400"})
        else
          HTTP::Client::Response.new(200, body: "", headers: HTTP::Headers{"Content-length" => "0"})
        end
      end

      options = default_test_options
      options.http_method = "get"
      options.retries = 1
      options.timeout = 1
      args = make_runner_args

      elapsed = Time.measure { Deadfinder::Runner.new.run(target, options, **args) }

      calls.should eq 2
      elapsed.should be < 5.seconds
      (args[:output][target]? || [] of String).should_not contain "http://example.com/hostile"
    end
  end

  describe "dead/alive policy" do
    it "keeps the built-in rule when no status flags are given" do
      link_flagged?(200, policy_options).should be_false
      link_flagged?(301, policy_options).should be_false
      link_flagged?(404, policy_options).should be_true
      link_flagged?(500, policy_options).should be_true
    end

    it "keeps --include30x working exactly as before" do
      options = policy_options
      options.include30x = true
      link_flagged?(301, options).should be_true

      options2 = policy_options
      options2.include30x = true
      link_flagged?(200, options2).should be_false
    end

    it "treats an accepted status as alive (LinkedIn's 999)" do
      options = policy_options
      options.accept_status = "999"
      link_flagged?(999, options).should be_false
    end

    it "treats an accepted status as alive (Cloudflare's 403 and a 429)" do
      options = policy_options
      options.accept_status = "403,429"
      link_flagged?(403, options).should be_false

      options2 = policy_options
      options2.accept_status = "403,429"
      options2.retries = 0
      link_flagged?(429, options2).should be_false
    end

    it "accepts a range" do
      options = policy_options
      options.accept_status = "400-499"
      link_flagged?(404, options).should be_false
      link_flagged?(500, options).should be_true
    end

    it "treats a listed status as dead even when it is a 2xx (soft 404)" do
      options = policy_options
      options.dead_status = "200"
      link_flagged?(200, options).should be_true
    end

    it "accepts --exclude-status as an alias that fills the same list" do
      options = Deadfinder::Options.new
      options.dead_status = "418"
      options.dead_status_ranges.should eq [418..418]
    end

    it "lets --accept-status win over --dead-status for a code in both" do
      options = policy_options
      options.accept_status = "403"
      options.dead_status = "400-499"
      link_flagged?(403, options).should be_false
      link_flagged?(404, options).should be_true
    end

    it "lets --accept-status win over --include30x" do
      options = policy_options
      options.include30x = true
      options.accept_status = "301"
      link_flagged?(301, options).should be_false
      link_flagged?(302, options).should be_true
    end
  end

  describe "--method end to end" do
    it "does not download a link body in auto mode when HEAD suffices" do
      target = "http://example.com"
      html = %(<html><body><a href="http://example.com/big">B</a></body></html>)
      WebMock.stub(:get, target).to_return(body: html)
      # Only HEAD is stubbed for the link: a GET would raise and be reported dead.
      WebMock.stub(:head, "http://example.com/big").to_return(status: 200)

      options = default_test_options
      args = make_runner_args

      Deadfinder::Runner.new.run(target, options, **args)

      (args[:output][target]? || [] of String).should be_empty
      args[:status_cache]["http://example.com/big"].should eq 200
    end

    it "does not report a link dead on a HEAD-only failure" do
      target = "http://example.com"
      html = %(<html><body><a href="http://example.com/headhostile">H</a></body></html>)
      WebMock.stub(:get, target).to_return(body: html)
      WebMock.stub(:head, "http://example.com/headhostile").to_return(status: 403)
      WebMock.stub(:get, "http://example.com/headhostile").to_return(status: 200)

      options = default_test_options
      args = make_runner_args

      Deadfinder::Runner.new.run(target, options, **args)

      (args[:output][target]? || [] of String).should be_empty
    end

    it "does not chase an unreachable HEAD with a pointless GET" do
      target = "http://example.com"
      html = %(<html><body><a href="http://unreachable.invalid/x">U</a></body></html>)
      WebMock.stub(:get, target).to_return(body: html)
      # Neither method is stubbed for the link, so both raise — standing in for
      # a host that cannot be reached at all. WebMock records what was tried.
      tried = [] of String
      WebMock.stub(:head, "http://unreachable.invalid/x").to_return do
        tried << "HEAD"
        raise Socket::ConnectError.new("Connect timed out")
      end
      WebMock.stub(:get, "http://unreachable.invalid/x").to_return do
        tried << "GET"
        raise Socket::ConnectError.new("Connect timed out")
      end

      options = default_test_options
      options.retries = 0
      args = make_runner_args

      Deadfinder::Runner.new.run(target, options, **args)

      # One attempt, one method: a GET cannot succeed where the TCP connect
      # itself failed, and spending a second full connect timeout proving that
      # doubled the cost of every unreachable link.
      tried.should eq ["HEAD"]
      args[:status_cache]["http://unreachable.invalid/x"].should eq Deadfinder::Runner::ERROR_STATUS
    end

    it "reports the HEAD status verbatim under --method=head" do
      target = "http://example.com"
      html = %(<html><body><a href="http://example.com/nohead">N</a></body></html>)
      WebMock.stub(:get, target).to_return(body: html)
      WebMock.stub(:head, "http://example.com/nohead").to_return(status: 405)

      options = default_test_options
      options.http_method = "head"
      options.retries = 0
      args = make_runner_args

      Deadfinder::Runner.new.run(target, options, **args)

      args[:output][target].should contain "http://example.com/nohead"
    end
  end

  describe "--delay" do
    it "spaces requests to one host without stalling another" do
      target = "http://example.com"
      html = <<-HTML
        <html><body>
          <a href="http://example.com/a">a</a>
          <a href="http://example.com/b">b</a>
          <a href="http://other.example/c">c</a>
        </body></html>
      HTML
      WebMock.stub(:get, target).to_return(body: html)
      ["http://example.com/a", "http://example.com/b", "http://other.example/c"].each do |url|
        WebMock.stub(:head, url).to_return(status: 200)
      end

      options = default_test_options
      options.retries = 0
      options.delay = 60
      args = make_runner_args

      elapsed = Time.measure { Deadfinder::Runner.new.run(target, options, **args) }

      # Two links on example.com must be at least one interval apart; the third,
      # on a different host, runs concurrently rather than adding a third slot.
      elapsed.should be >= 50.milliseconds
      (args[:output][target]? || [] of String).should be_empty
    end
  end
end
