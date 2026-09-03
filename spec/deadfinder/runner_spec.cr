require "../spec_helper"

describe Deadfinder::Runner do
  before_each { WebMock.reset }

  describe "#run" do
    it "finds broken links (404)" do
      target = "http://example.com"
      html = <<-HTML
        <html><body>
          <a href="http://example.com/broken">Broken</a>
          <a href="http://example.com/valid">Valid</a>
        </body></html>
      HTML

      WebMock.stub(:get, target).to_return(body: html)
      WebMock.stub(:get, "http://example.com/broken").to_return(status: 404)
      WebMock.stub(:get, "http://example.com/valid").to_return(status: 200)

      runner = Deadfinder::Runner.new
      options = default_test_options
      args = make_runner_args

      runner.run(target, options, **args)

      args[:output][target]?.should_not be_nil
      args[:output][target].should contain "http://example.com/broken"
      args[:output][target].should_not contain "http://example.com/valid"
    end

    it "finds multiple broken links" do
      target = "http://example.com"
      html = <<-HTML
        <html><body>
          <a href="http://example.com/dead1">D1</a>
          <a href="http://example.com/dead2">D2</a>
          <a href="http://example.com/ok">OK</a>
        </body></html>
      HTML

      WebMock.stub(:get, target).to_return(body: html)
      WebMock.stub(:get, "http://example.com/dead1").to_return(status: 404)
      WebMock.stub(:get, "http://example.com/dead2").to_return(status: 500)
      WebMock.stub(:get, "http://example.com/ok").to_return(status: 200)

      runner = Deadfinder::Runner.new
      options = default_test_options
      args = make_runner_args

      runner.run(target, options, **args)

      args[:output][target].should contain "http://example.com/dead1"
      args[:output][target].should contain "http://example.com/dead2"
      args[:output][target].should_not contain "http://example.com/ok"
    end

    it "does not flag 3xx as dead by default" do
      target = "http://example.com"
      html = %(<html><body><a href="http://example.com/redirect">R</a></body></html>)

      WebMock.stub(:get, target).to_return(body: html)
      WebMock.stub(:get, "http://example.com/redirect").to_return(status: 301)

      runner = Deadfinder::Runner.new
      options = default_test_options
      args = make_runner_args

      runner.run(target, options, **args)

      (args[:output][target]? || [] of String).should_not contain "http://example.com/redirect"
    end

    it "flags 3xx as dead when include30x is true" do
      target = "http://example.com"
      html = %(<html><body><a href="http://example.com/redirect">R</a></body></html>)

      WebMock.stub(:get, target).to_return(body: html)
      WebMock.stub(:get, "http://example.com/redirect").to_return(status: 301)

      runner = Deadfinder::Runner.new
      options = default_test_options
      options.include30x = true
      args = make_runner_args

      runner.run(target, options, **args)

      args[:output][target]?.should_not be_nil
      args[:output][target].should contain "http://example.com/redirect"
    end

    it "respects match option - only checks matched URLs" do
      target = "http://example.com"
      html = <<-HTML
        <html><body>
          <a href="http://example.com/broken">Broken</a>
          <a href="http://example.com/valid">Valid</a>
        </body></html>
      HTML

      WebMock.stub(:get, target).to_return(body: html)
      WebMock.stub(:get, "http://example.com/broken").to_return(status: 404)
      # valid은 match 안 하므로 stub 불필요하지만 안전하게 추가
      WebMock.stub(:get, "http://example.com/valid").to_return(status: 200)

      runner = Deadfinder::Runner.new
      options = default_test_options
      options.match = "broken"
      args = make_runner_args

      runner.run(target, options, **args)

      args[:output][target]?.should_not be_nil
      args[:output][target].should contain "http://example.com/broken"
    end

    it "respects ignore option - skips ignored URLs" do
      target = "http://example.com"
      html = <<-HTML
        <html><body>
          <a href="http://example.com/broken">Broken</a>
          <a href="http://example.com/valid">Valid</a>
        </body></html>
      HTML

      WebMock.stub(:get, target).to_return(body: html)
      WebMock.stub(:get, "http://example.com/broken").to_return(status: 404)

      runner = Deadfinder::Runner.new
      options = default_test_options
      options.ignore = "valid"
      args = make_runner_args

      runner.run(target, options, **args)

      args[:output][target]?.should_not be_nil
      args[:output][target].should contain "http://example.com/broken"
      args[:output][target].should_not contain "http://example.com/valid"
    end

    it "handles invalid match pattern gracefully" do
      target = "http://example.com"
      html = %(<html><body><a href="http://example.com/page">Link</a></body></html>)

      WebMock.stub(:get, target).to_return(body: html)
      WebMock.stub(:get, "http://example.com/page").to_return(status: 200)

      runner = Deadfinder::Runner.new
      options = default_test_options
      options.match = "["
      args = make_runner_args

      # Should not raise - error is logged internally
      runner.run(target, options, **args)
    end

    it "handles invalid ignore pattern gracefully" do
      target = "http://example.com"
      html = %(<html><body><a href="http://example.com/page">Link</a></body></html>)

      WebMock.stub(:get, target).to_return(body: html)
      WebMock.stub(:get, "http://example.com/page").to_return(status: 200)

      runner = Deadfinder::Runner.new
      options = default_test_options
      options.ignore = "["
      args = make_runner_args

      # Should not raise
      runner.run(target, options, **args)
    end

    it "handles target fetch failure gracefully" do
      target = "http://unreachable.invalid"
      WebMock.stub(:get, target).to_return(status: 500, body: "")

      runner = Deadfinder::Runner.new
      options = default_test_options
      args = make_runner_args

      # Should not raise
      runner.run(target, options, **args)
    end

    it "extracts links from all 7 HTML element types" do
      target = "http://example.com"
      html = <<-HTML
        <html>
        <head>
          <script src="http://example.com/script.js"></script>
          <link href="http://example.com/style.css">
        </head>
        <body>
          <a href="http://example.com/page">Link</a>
          <iframe src="http://example.com/frame"></iframe>
          <form action="http://example.com/submit"></form>
          <object data="http://example.com/object.swf"></object>
          <embed src="http://example.com/embed.swf">
        </body></html>
      HTML

      WebMock.stub(:get, target).to_return(body: html)
      WebMock.stub(:get, "http://example.com/script.js").to_return(status: 404)
      WebMock.stub(:get, "http://example.com/style.css").to_return(status: 404)
      WebMock.stub(:get, "http://example.com/page").to_return(status: 404)
      WebMock.stub(:get, "http://example.com/frame").to_return(status: 404)
      WebMock.stub(:get, "http://example.com/submit").to_return(status: 404)
      WebMock.stub(:get, "http://example.com/object.swf").to_return(status: 404)
      WebMock.stub(:get, "http://example.com/embed.swf").to_return(status: 404)

      runner = Deadfinder::Runner.new
      options = default_test_options
      args = make_runner_args

      runner.run(target, options, **args)

      dead = args[:output][target]
      dead.should contain "http://example.com/script.js"
      dead.should contain "http://example.com/style.css"
      dead.should contain "http://example.com/page"
      dead.should contain "http://example.com/frame"
      dead.should contain "http://example.com/submit"
      dead.should contain "http://example.com/object.swf"
      dead.should contain "http://example.com/embed.swf"
    end

    it "resolves relative URLs against target" do
      target = "http://example.com/docs/"
      html = %(<html><body><a href="/about">About</a><a href="page.html">Page</a></body></html>)

      WebMock.stub(:get, target).to_return(body: html)
      WebMock.stub(:get, "http://example.com/about").to_return(status: 404)
      WebMock.stub(:get, "http://example.com/docs/page.html").to_return(status: 404)

      runner = Deadfinder::Runner.new
      options = default_test_options
      args = make_runner_args

      runner.run(target, options, **args)

      dead = args[:output][target]
      dead.should contain "http://example.com/about"
      dead.should contain "http://example.com/docs/page.html"
    end

    it "skips mailto/tel/data scheme links" do
      target = "http://example.com"
      html = <<-HTML
        <html><body>
          <a href="mailto:test@example.com">Mail</a>
          <a href="tel:1234567890">Tel</a>
          <a href="data:text/plain,hello">Data</a>
          <a href="http://example.com/real">Real</a>
        </body></html>
      HTML

      WebMock.stub(:get, target).to_return(body: html)
      WebMock.stub(:get, "http://example.com/real").to_return(status: 200)

      runner = Deadfinder::Runner.new
      options = default_test_options
      args = make_runner_args

      runner.run(target, options, **args)

      # No dead links from special schemes, and no errors
      dead = args[:output][target]? || [] of String
      dead.should_not contain "mailto:test@example.com"
      dead.should_not contain "tel:1234567890"
    end

    it "deduplicates URLs" do
      target = "http://example.com"
      html = <<-HTML
        <html><body>
          <a href="http://example.com/dup">Link1</a>
          <a href="http://example.com/dup">Link2</a>
          <a href="http://example.com/dup">Link3</a>
        </body></html>
      HTML

      WebMock.stub(:get, target).to_return(body: html)
      WebMock.stub(:get, "http://example.com/dup").to_return(status: 404)

      runner = Deadfinder::Runner.new
      options = default_test_options
      args = make_runner_args

      runner.run(target, options, **args)

      # Should appear only once in output
      args[:output][target].count("http://example.com/dup").should eq 1
    end

    it "tracks coverage data when coverage is enabled" do
      target = "http://example.com"
      html = <<-HTML
        <html><body>
          <a href="http://example.com/dead">Dead</a>
          <a href="http://example.com/ok1">Ok1</a>
          <a href="http://example.com/ok2">Ok2</a>
        </body></html>
      HTML

      WebMock.stub(:get, target).to_return(body: html)
      WebMock.stub(:get, "http://example.com/dead").to_return(status: 404)
      WebMock.stub(:get, "http://example.com/ok1").to_return(status: 200)
      WebMock.stub(:get, "http://example.com/ok2").to_return(status: 200)

      runner = Deadfinder::Runner.new
      options = default_test_options
      options.coverage = true
      args = make_runner_args

      runner.run(target, options, **args)

      cov = args[:coverage_data][target]
      cov.total.should eq 3
      cov.dead.should eq 1
      cov.status_counts["404"].should eq 1
      cov.status_counts["200"].should eq 2
    end

    it "does not track coverage when coverage is disabled" do
      target = "http://example.com"
      html = %(<html><body><a href="http://example.com/page">L</a></body></html>)

      WebMock.stub(:get, target).to_return(body: html)
      WebMock.stub(:get, "http://example.com/page").to_return(status: 404)

      runner = Deadfinder::Runner.new
      options = default_test_options
      options.coverage = false
      args = make_runner_args

      runner.run(target, options, **args)

      args[:coverage_data][target]?.should be_nil
    end

    it "handles empty HTML page with no links" do
      target = "http://example.com"
      WebMock.stub(:get, target).to_return(body: "<html><body></body></html>")

      runner = Deadfinder::Runner.new
      options = default_test_options
      args = make_runner_args

      runner.run(target, options, **args)

      (args[:output][target]? || [] of String).should be_empty
    end

    it "does not deadlock when scanning a page with more links than the channel buffer size (1000)" do
      target = "http://example.com/large"

      # Generate 1050 links
      links_html = (1..1050).map { |i| "<a href='http://example.com/link-#{i}'>L#{i}</a>" }.join("\n")
      html = "<html><body>#{links_html}</body></html>"

      WebMock.stub(:get, target).to_return(body: html)

      # Mock all 1050 link targets to return 200 OK quickly
      (1..1050).each do |i|
        WebMock.stub(:get, "http://example.com/link-#{i}").to_return(status: 200)
      end

      runner = Deadfinder::Runner.new
      options = default_test_options
      options.concurrency = 10
      args = make_runner_args

      # This should finish successfully and NOT deadlock
      runner.run(target, options, **args)

      (args[:output][target]? || [] of String).should be_empty
    end

    it "does not hang when concurrency is 0 (clamps to at least one worker)" do
      target = "http://example.com/zero"
      html = %(<html><body><a href="http://example.com/x">x</a></body></html>)
      WebMock.stub(:get, target).to_return(body: html)
      WebMock.stub(:get, "http://example.com/x").to_return(status: 200)

      runner = Deadfinder::Runner.new
      options = default_test_options
      options.concurrency = 0
      args = make_runner_args

      # With the unclamped code this blocked forever on results.receive.
      runner.run(target, options, **args)

      (args[:output][target]? || [] of String).should be_empty
    end

    it "attributes a shared dead link to every referencing page and fetches it once" do
      page_a = "http://multi.test/a"
      page_b = "http://multi.test/b"
      dead = "http://multi.test/dead"

      WebMock.stub(:get, page_a).to_return(body: %(<html><body><a href="#{dead}">x</a></body></html>))
      WebMock.stub(:get, page_b).to_return(body: %(<html><body><a href="#{dead}">y</a></body></html>))

      fetch_count = 0
      WebMock.stub(:get, dead).to_return do
        fetch_count += 1
        HTTP::Client::Response.new(404, "")
      end

      options = default_test_options
      args = make_runner_args

      # Same output/status_cache shared across both target runs (as in real runs).
      Deadfinder::Runner.new.run(page_a, options, **args)
      Deadfinder::Runner.new.run(page_b, options, **args)

      args[:output][page_a].should contain dead
      args[:output][page_b].should contain dead # previously only page_a got it
      fetch_count.should eq 1                   # but the URL is fetched only once
    end

    it "records a URL once per page when distinct links resolve to the same URL" do
      target = "http://dedup.test/"
      html = <<-HTML
        <html><body>
          <a href="/dead">absolute</a>
          <a href="dead">relative</a>
          <a href="./dead">dot-relative</a>
        </body></html>
      HTML
      WebMock.stub(:get, target).to_return(body: html)
      WebMock.stub(:get, "http://dedup.test/dead").to_return(status: 404)

      runner = Deadfinder::Runner.new
      options = default_test_options
      args = make_runner_args

      runner.run(target, options, **args)

      args[:output][target].count("http://dedup.test/dead").should eq 1
    end
  end

  describe "#worker" do
    it "detects 404 as broken link" do
      target = "http://example.com"
      url = "http://example.com/broken"

      WebMock.stub(:get, url).to_return(status: 404)

      runner = Deadfinder::Runner.new
      options = default_test_options
      args = make_runner_args

      jobs = Channel(Tuple(String, Array(String))).new(10)
      results = Channel(Nil).new(10)
      jobs.send(job_for(url))
      jobs.close

      runner.worker(1, jobs, results, target, options, **args)

      args[:output][target].should contain url
    end

    it "detects 500 as broken link" do
      target = "http://example.com"
      url = "http://example.com/error"

      WebMock.stub(:get, url).to_return(status: 500)

      runner = Deadfinder::Runner.new
      options = default_test_options
      args = make_runner_args

      jobs = Channel(Tuple(String, Array(String))).new(10)
      results = Channel(Nil).new(10)
      jobs.send(job_for(url))
      jobs.close

      runner.worker(1, jobs, results, target, options, **args)

      args[:output][target].should contain url
    end

    it "does not flag 200 as broken" do
      target = "http://example.com"
      url = "http://example.com/ok"

      WebMock.stub(:get, url).to_return(status: 200)

      runner = Deadfinder::Runner.new
      options = default_test_options
      args = make_runner_args

      jobs = Channel(Tuple(String, Array(String))).new(10)
      results = Channel(Nil).new(10)
      jobs.send(job_for(url))
      jobs.close

      runner.worker(1, jobs, results, target, options, **args)

      (args[:output][target]? || [] of String).should_not contain url
    end

    it "does not flag 301 as broken without include30x" do
      target = "http://example.com"
      url = "http://example.com/moved"

      WebMock.stub(:get, url).to_return(status: 301)

      runner = Deadfinder::Runner.new
      options = default_test_options
      options.include30x = false
      args = make_runner_args

      jobs = Channel(Tuple(String, Array(String))).new(10)
      results = Channel(Nil).new(10)
      jobs.send(job_for(url))
      jobs.close

      runner.worker(1, jobs, results, target, options, **args)

      (args[:output][target]? || [] of String).should_not contain url
    end

    it "flags 301 as broken with include30x" do
      target = "http://example.com"
      url = "http://example.com/moved"

      WebMock.stub(:get, url).to_return(status: 301)

      runner = Deadfinder::Runner.new
      options = default_test_options
      options.include30x = true
      args = make_runner_args

      jobs = Channel(Tuple(String, Array(String))).new(10)
      results = Channel(Nil).new(10)
      jobs.send(job_for(url))
      jobs.close

      runner.worker(1, jobs, results, target, options, **args)

      args[:output][target].should contain url
    end

    it "reuses a cached status without re-fetching, still attributing it to the target" do
      target = "http://example.com"
      url = "http://example.com/cached"

      # No WebMock stub on purpose: if the worker tried to fetch, WebMock raises.
      runner = Deadfinder::Runner.new
      options = default_test_options
      args = make_runner_args
      # Pre-populate the status cache as if a previous page already checked it.
      args[:status_cache][url] = 404

      jobs = Channel(Tuple(String, Array(String))).new(10)
      results = Channel(Nil).new(10)
      jobs.send(job_for(url))
      jobs.close

      runner.worker(1, jobs, results, target, options, **args)

      # The cached dead status is attributed to this target without a 2nd request.
      args[:output][target].should contain url
    end

    it "processes multiple jobs sequentially" do
      target = "http://example.com"

      WebMock.stub(:get, "http://example.com/a").to_return(status: 404)
      WebMock.stub(:get, "http://example.com/b").to_return(status: 200)
      WebMock.stub(:get, "http://example.com/c").to_return(status: 503)

      runner = Deadfinder::Runner.new
      options = default_test_options
      args = make_runner_args

      jobs = Channel(Tuple(String, Array(String))).new(10)
      results = Channel(Nil).new(10)
      jobs.send(job_for("http://example.com/a"))
      jobs.send(job_for("http://example.com/b"))
      jobs.send(job_for("http://example.com/c"))
      jobs.close

      runner.worker(1, jobs, results, target, options, **args)

      dead = args[:output][target]
      dead.should contain "http://example.com/a"
      dead.should_not contain "http://example.com/b"
      dead.should contain "http://example.com/c"
    end

    it "tracks coverage with status counts" do
      target = "http://example.com"

      WebMock.stub(:get, "http://example.com/ok").to_return(status: 200)
      WebMock.stub(:get, "http://example.com/not-found").to_return(status: 404)
      WebMock.stub(:get, "http://example.com/server-err").to_return(status: 500)

      runner = Deadfinder::Runner.new
      options = default_test_options
      options.coverage = true
      args = make_runner_args

      jobs = Channel(Tuple(String, Array(String))).new(10)
      results = Channel(Nil).new(10)
      jobs.send(job_for("http://example.com/ok"))
      jobs.send(job_for("http://example.com/not-found"))
      jobs.send(job_for("http://example.com/server-err"))
      jobs.close

      runner.worker(1, jobs, results, target, options, **args)

      cov = args[:coverage_data][target]
      cov.total.should eq 3
      cov.dead.should eq 2
      cov.status_counts["200"].should eq 1
      cov.status_counts["404"].should eq 1
      cov.status_counts["500"].should eq 1
    end

    it "sends worker_headers with requests" do
      target = "http://example.com"
      url = "http://example.com/authed"

      WebMock.stub(:get, url)
        .with(headers: {"Authorization" => "Bearer token123"})
        .to_return(status: 200)

      runner = Deadfinder::Runner.new
      options = default_test_options
      options.worker_headers = ["Authorization: Bearer token123"]
      args = make_runner_args

      jobs = Channel(Tuple(String, Array(String))).new(10)
      results = Channel(Nil).new(10)
      jobs.send(job_for(url))
      jobs.close

      runner.worker(1, jobs, results, target, options, **args)

      # Should not be in dead links (200 response with correct headers)
      (args[:output][target]? || [] of String).should_not contain url
    end

    it "honors a User-Agent supplied via headers instead of the default" do
      target = "http://example.com"
      url = "http://example.com/ua"
      WebMock.stub(:get, url)
        .with(headers: {"User-Agent" => "my-custom-agent"})
        .to_return(status: 200)

      runner = Deadfinder::Runner.new
      options = default_test_options
      options.worker_headers = ["User-Agent: my-custom-agent"]
      args = make_runner_args

      jobs = Channel(Tuple(String, Array(String))).new(10)
      results = Channel(Nil).new(10)
      jobs.send(job_for(url))
      jobs.close

      runner.worker(1, jobs, results, target, options, **args)

      # 200 only matches when the custom UA is sent; if the default UA overrode
      # it, WebMock would not match, the request would raise, and url would be
      # recorded as dead.
      (args[:output][target]? || [] of String).should_not contain url
    end

    it "detects socket/connection exceptions as broken links" do
      target = "http://example.com"
      url = "http://example.com/timeout"

      WebMock.stub(:get, url).to_return { raise IO::TimeoutError.new("Connection timeout") }

      runner = Deadfinder::Runner.new
      options = default_test_options
      args = make_runner_args

      jobs = Channel(Tuple(String, Array(String))).new(10)
      results = Channel(Nil).new(10)
      jobs.send(job_for(url))
      jobs.close

      runner.worker(1, jobs, results, target, options, **args)

      # Should be flagged as broken and present in the output
      args[:output][target].should contain url
    end

    it "tracks error/exception coverage when coverage is enabled" do
      target = "http://example.com"
      url = "http://example.com/connrefused"

      WebMock.stub(:get, url).to_return { raise Socket::Error.new("Connection refused") }

      runner = Deadfinder::Runner.new
      options = default_test_options
      options.coverage = true
      args = make_runner_args

      jobs = Channel(Tuple(String, Array(String))).new(10)
      results = Channel(Nil).new(10)
      jobs.send(job_for(url))
      jobs.close

      runner.worker(1, jobs, results, target, options, **args)

      cov = args[:coverage_data][target]
      cov.total.should eq 1
      cov.dead.should eq 1
      cov.status_counts["error"].should eq 1
    end
  end
end

describe Deadfinder::Runner do
  before_each { WebMock.reset }

  describe "#run redirect handling" do
    it "follows a redirected target page instead of parsing an empty body" do
      WebMock.stub(:get, "http://moved.test/")
        .to_return(status: 301, headers: {"Location" => "http://moved.test/home"})
      WebMock.stub(:get, "http://moved.test/home")
        .to_return(body: %(<html><body><a href="http://moved.test/dead">d</a></body></html>))
      WebMock.stub(:get, "http://moved.test/dead").to_return(status: 404)

      args = make_runner_args
      Deadfinder::Runner.new.run("http://moved.test/", default_test_options, **args)

      # Output stays keyed by the target the user asked for.
      args[:output]["http://moved.test/"].should contain "http://moved.test/dead"
    end

    it "resolves relative links against the post-redirect location" do
      WebMock.stub(:get, "http://rel.test/old")
        .to_return(status: 302, headers: {"Location" => "http://rel.test/new/page"})
      WebMock.stub(:get, "http://rel.test/new/page")
        .to_return(body: %(<html><body><a href="sibling">s</a></body></html>))
      WebMock.stub(:get, "http://rel.test/new/sibling").to_return(status: 404)

      args = make_runner_args
      Deadfinder::Runner.new.run("http://rel.test/old", default_test_options, **args)

      args[:output]["http://rel.test/old"].should eq ["http://rel.test/new/sibling"]
    end

    it "still reports link redirects verbatim without following them" do
      followed = false
      WebMock.stub(:get, "http://link.test/")
        .to_return(body: %(<html><body><a href="http://link.test/moved">m</a></body></html>))
      WebMock.stub(:get, "http://link.test/moved")
        .to_return(status: 301, headers: {"Location" => "http://link.test/final"})
      WebMock.stub(:get, "http://link.test/final").to_return do
        followed = true
        HTTP::Client::Response.new(200, body: "")
      end

      options = default_test_options
      options.include30x = true
      args = make_runner_args
      Deadfinder::Runner.new.run("http://link.test/", options, **args)

      followed.should be_false
      args[:output]["http://link.test/"].should contain "http://link.test/moved"
    end
  end

  describe "#run base href handling" do
    it "resolves relative links against <base href>" do
      html = %(<html><head><base href="http://base.test/docs/"></head><body><a href="guide">g</a></body></html>)
      WebMock.stub(:get, "http://base.test/index.html").to_return(body: html)
      WebMock.stub(:get, "http://base.test/docs/guide").to_return(status: 404)

      args = make_runner_args
      Deadfinder::Runner.new.run("http://base.test/index.html", default_test_options, **args)

      args[:output]["http://base.test/index.html"].should eq ["http://base.test/docs/guide"]
    end

    it "accepts a relative <base href>" do
      html = %(<html><head><base href="/docs/"></head><body><a href="guide">g</a></body></html>)
      WebMock.stub(:get, "http://relbase.test/a/index.html").to_return(body: html)
      WebMock.stub(:get, "http://relbase.test/docs/guide").to_return(status: 404)

      args = make_runner_args
      Deadfinder::Runner.new.run("http://relbase.test/a/index.html", default_test_options, **args)

      args[:output]["http://relbase.test/a/index.html"].should eq ["http://relbase.test/docs/guide"]
    end

    it "ignores an empty <base href> and falls back to the page URL" do
      html = %(<html><head><base href=""></head><body><a href="guide">g</a></body></html>)
      WebMock.stub(:get, "http://emptybase.test/a/index.html").to_return(body: html)
      WebMock.stub(:get, "http://emptybase.test/a/guide").to_return(status: 404)

      args = make_runner_args
      Deadfinder::Runner.new.run("http://emptybase.test/a/index.html", default_test_options, **args)

      args[:output]["http://emptybase.test/a/index.html"].should eq ["http://emptybase.test/a/guide"]
    end
  end

  describe "#run fragment handling" do
    it "requests a URL once for links that differ only by fragment" do
      requests = 0
      html = %(<html><body>
        <a href="http://frag.test/guide#install">i</a>
        <a href="http://frag.test/guide#usage">u</a>
      </body></html>)
      WebMock.stub(:get, "http://frag.test/index.html").to_return(body: html)
      WebMock.stub(:get, "http://frag.test/guide").to_return do
        requests += 1
        HTTP::Client::Response.new(404, body: "")
      end

      options = default_test_options
      options.coverage = true
      args = make_runner_args
      Deadfinder::Runner.new.run("http://frag.test/index.html", options, **args)

      requests.should eq 1
      # Both link instances are still reported, so the user can find each one.
      args[:output]["http://frag.test/index.html"].sort.should eq [
        "http://frag.test/guide#install",
        "http://frag.test/guide#usage",
      ]
      args[:coverage_data]["http://frag.test/index.html"].total.should eq 2
    end
  end

  describe "#run cross-target request de-duplication" do
    it "requests a URL shared by two concurrently scanned targets only once" do
      link = %(<a href="http://shared.test/x">s</a>)
      WebMock.stub(:get, "http://a.test").to_return(body: "<html><body>#{link}</body></html>")
      WebMock.stub(:get, "http://b.test").to_return(body: "<html><body>#{link}</body></html>")
      # Sleeping inside the stub yields the fiber mid-request, which is exactly
      # the window in which the second target used to issue a duplicate request:
      # both miss the status cache, because neither has written it yet.
      shared = WebMock.stub(:get, "http://shared.test/x").to_return do
        sleep 20.milliseconds
        HTTP::Client::Response.new(404, body: "")
      end

      options = default_test_options
      args = make_runner_args
      runner = Deadfinder::Runner.new

      done = Channel(Nil).new
      ["http://a.test", "http://b.test"].each do |target|
        spawn do
          runner.run(target, options, **args)
          done.send(nil)
        end
      end
      2.times { done.receive }

      shared.calls.should eq 1
      # The second requester still gets the status attributed to its own target
      # rather than silently dropping the link.
      args[:output]["http://a.test"].should contain "http://shared.test/x"
      args[:output]["http://b.test"].should contain "http://shared.test/x"
      args[:status_cache]["http://shared.test/x"].should eq 404
    end

    it "lets a waiter fall through to its own request when the fetch failed" do
      link = %(<a href="http://unreachable.test/x">s</a>)
      WebMock.stub(:get, "http://c.test").to_return(body: "<html><body>#{link}</body></html>")
      WebMock.stub(:get, "http://d.test").to_return(body: "<html><body>#{link}</body></html>")
      # No stub for unreachable.test: every fetch raises, so the owner records
      # ERROR_STATUS. The in-flight entry must still be cleared, otherwise the
      # waiter would block on a channel nobody ever closes.
      options = default_test_options
      args = make_runner_args
      runner = Deadfinder::Runner.new

      done = Channel(Nil).new
      ["http://c.test", "http://d.test"].each do |target|
        spawn do
          runner.run(target, options, **args)
          done.send(nil)
        end
      end
      2.times { done.receive }

      args[:status_cache]["http://unreachable.test/x"].should eq Deadfinder::Runner::ERROR_STATUS
      args[:output]["http://c.test"].should contain "http://unreachable.test/x"
      args[:output]["http://d.test"].should contain "http://unreachable.test/x"
    end
  end
end

describe Deadfinder::RequestPermits do
  it "never lets more than `size` blocks run at once" do
    permits = Deadfinder::RequestPermits.new(3)
    inflight = 0
    peak = 0
    done = Channel(Nil).new

    10.times do
      spawn do
        permits.acquire do
          inflight += 1
          peak = inflight if inflight > peak
          sleep 2.milliseconds
          inflight -= 1
        end
        done.send(nil)
      end
    end
    10.times { done.receive }

    peak.should eq 3
    inflight.should eq 0
  end

  it "clamps a non-positive size to one" do
    Deadfinder::RequestPermits.new(0).size.should eq 1
    Deadfinder::RequestPermits.new(-5).size.should eq 1
  end

  it "returns the permit when the block raises" do
    permits = Deadfinder::RequestPermits.new(1)
    expect_raises(Exception, "boom") { permits.acquire { raise "boom" } }
    # The slot has to be free again; otherwise the next acquire hangs forever.
    permits.acquire { 42 }.should eq 42
  end

  it "reuses one pool per size so every target draws from the same budget" do
    pool = Deadfinder::Runner.permits(7)
    pool.size.should eq 7
    Deadfinder::Runner.permits(7).should be pool
    Deadfinder::Runner.permits(9).should_not be pool
  end
end

describe Deadfinder::Runner do
  before_each { WebMock.reset }

  describe "#run media and image extraction" do
    it "extracts img/source/video/audio/track/area resources" do
      target = "http://media.test/"
      html = <<-HTML
        <html><body>
          <img src="/i.png">
          <picture><source srcset="/p.webp"></picture>
          <video src="/v.mp4" poster="/poster.jpg">
            <source src="/v.webm">
            <track src="/subs.vtt">
          </video>
          <audio src="/a.mp3"></audio>
          <map><area href="/region"></map>
        </body></html>
      HTML

      WebMock.stub(:get, target).to_return(body: html)
      %w[/i.png /p.webp /v.mp4 /poster.jpg /v.webm /subs.vtt /a.mp3 /region].each do |path|
        WebMock.stub(:get, "http://media.test#{path}").to_return(status: 404)
      end

      args = make_runner_args
      Deadfinder::Runner.new.run(target, default_test_options, **args)

      dead = args[:output][target]
      dead.should contain "http://media.test/i.png"
      dead.should contain "http://media.test/p.webp"
      dead.should contain "http://media.test/v.mp4"
      dead.should contain "http://media.test/poster.jpg"
      dead.should contain "http://media.test/v.webm"
      dead.should contain "http://media.test/subs.vtt"
      dead.should contain "http://media.test/a.mp3"
      dead.should contain "http://media.test/region"
      dead.size.should eq 8
    end

    it "still extracts the seven original element types" do
      target = "http://legacy.test/"
      html = <<-HTML
        <html><head>
          <script src="/s.js"></script>
          <link href="/s.css">
        </head><body>
          <a href="/page">a</a>
          <iframe src="/frame"></iframe>
          <form action="/submit"></form>
          <object data="/o.swf"></object>
          <embed src="/e.swf">
        </body></html>
      HTML

      WebMock.stub(:get, target).to_return(body: html)
      %w[/s.js /s.css /page /frame /submit /o.swf /e.swf].each do |path|
        WebMock.stub(:get, "http://legacy.test#{path}").to_return(status: 404)
      end

      args = make_runner_args
      Deadfinder::Runner.new.run(target, default_test_options, **args)

      args[:output][target].size.should eq 7
    end
  end

  describe "#run srcset parsing" do
    it "extracts each candidate URL and drops the descriptors" do
      target = "http://srcset.test/"
      html = %(<html><body><img srcset="/img-480.png 480w, /img-2x.png 2x"></body></html>)

      WebMock.stub(:get, target).to_return(body: html)
      WebMock.stub(:get, "http://srcset.test/img-480.png").to_return(status: 404)
      WebMock.stub(:get, "http://srcset.test/img-2x.png").to_return(status: 404)

      args = make_runner_args
      Deadfinder::Runner.new.run(target, default_test_options, **args)

      args[:output][target].sort.should eq [
        "http://srcset.test/img-2x.png",
        "http://srcset.test/img-480.png",
      ]
    end

    it "keeps commas that belong to the URL instead of splitting on them" do
      target = "http://comma.test/"
      html = %(<html><body><img srcset="/a,b.png 1x, /c.png 2x"></body></html>)

      WebMock.stub(:get, target).to_return(body: html)
      WebMock.stub(:get, "http://comma.test/a,b.png").to_return(status: 404)
      WebMock.stub(:get, "http://comma.test/c.png").to_return(status: 404)

      args = make_runner_args
      Deadfinder::Runner.new.run(target, default_test_options, **args)

      args[:output][target].sort.should eq [
        "http://comma.test/a,b.png",
        "http://comma.test/c.png",
      ]
    end

    it "splits candidates that carry no descriptor at all" do
      target = "http://nodesc.test/"
      html = %(<html><body><source srcset="  /a.png ,   /b.png  "></body></html>)

      WebMock.stub(:get, target).to_return(body: html)
      WebMock.stub(:get, "http://nodesc.test/a.png").to_return(status: 404)
      WebMock.stub(:get, "http://nodesc.test/b.png").to_return(status: 404)

      args = make_runner_args
      Deadfinder::Runner.new.run(target, default_test_options, **args)

      args[:output][target].sort.should eq [
        "http://nodesc.test/a.png",
        "http://nodesc.test/b.png",
      ]
    end

    it "ignores an empty or whitespace-only srcset" do
      target = "http://empty.test/"
      html = %(<html><body><img srcset="   ,  , "><img src="/real.png"></body></html>)

      WebMock.stub(:get, target).to_return(body: html)
      WebMock.stub(:get, "http://empty.test/real.png").to_return(status: 404)

      args = make_runner_args
      Deadfinder::Runner.new.run(target, default_test_options, **args)

      args[:output][target].should eq ["http://empty.test/real.png"]
    end
  end

  describe "#run anchor checking" do
    doc = %(<html><body><h1 id="install">i</h1><a name="legacy"></a><div id="\u{d55c}\u{ae00}"></div></body></html>)

    it "does not check fragments unless --check-anchors is given" do
      WebMock.stub(:get, "http://anchor.test/")
        .to_return(body: %(<html><body><a href="/guide#nope">n</a></body></html>))
      WebMock.stub(:get, "http://anchor.test/guide")
        .to_return(status: 200, body: doc, headers: {"Content-Type" => "text/html"})

      args = make_runner_args
      Deadfinder::Runner.new.run("http://anchor.test/", default_test_options, **args)

      (args[:output]["http://anchor.test/"]? || [] of String).should be_empty
    end

    it "reports a fragment with no matching id as dead" do
      WebMock.stub(:get, "http://anchor.test/")
        .to_return(body: %(<html><body><a href="/guide#nope">n</a></body></html>))
      WebMock.stub(:get, "http://anchor.test/guide")
        .to_return(status: 200, body: doc, headers: {"Content-Type" => "text/html"})

      options = default_test_options
      options.check_anchors = true
      args = make_runner_args
      Deadfinder::Runner.new.run("http://anchor.test/", options, **args)

      args[:output]["http://anchor.test/"].should eq ["http://anchor.test/guide#nope"]
    end

    it "accepts a fragment matching an id, a legacy <a name>, or a percent-encoded id" do
      html = %(<html><body>
        <a href="/guide#install">a</a>
        <a href="/guide#legacy">b</a>
        <a href="/guide#%ED%95%9C%EA%B8%80">c</a>
      </body></html>)
      WebMock.stub(:get, "http://ok-anchor.test/").to_return(body: html)
      WebMock.stub(:get, "http://ok-anchor.test/guide")
        .to_return(status: 200, body: doc, headers: {"Content-Type" => "text/html"})

      options = default_test_options
      options.check_anchors = true
      args = make_runner_args
      Deadfinder::Runner.new.run("http://ok-anchor.test/", options, **args)

      (args[:output]["http://ok-anchor.test/"]? || [] of String).should be_empty
    end

    it "treats #top and an empty fragment as valid by definition" do
      html = %(<html><body>
        <a href="/guide#top">t</a>
        <a href="/guide#TOP">T</a>
        <a href="/guide#">e</a>
      </body></html>)
      WebMock.stub(:get, "http://top.test/").to_return(body: html)
      WebMock.stub(:get, "http://top.test/guide")
        .to_return(status: 200, body: doc, headers: {"Content-Type" => "text/html"})

      options = default_test_options
      options.check_anchors = true
      args = make_runner_args
      Deadfinder::Runner.new.run("http://top.test/", options, **args)

      (args[:output]["http://top.test/"]? || [] of String).should be_empty
    end

    it "opens the linked document once no matter how many fragments point at it" do
      requests = 0
      html = %(<html><body>
        <a href="/guide#install">a</a>
        <a href="/guide#nope1">b</a>
        <a href="/guide#nope2">c</a>
      </body></html>)
      WebMock.stub(:get, "http://once.test/").to_return(body: html)
      WebMock.stub(:get, "http://once.test/guide").to_return do
        requests += 1
        HTTP::Client::Response.new(200, body: doc, headers: HTTP::Headers{"Content-Type" => "text/html"})
      end

      options = default_test_options
      options.check_anchors = true
      args = make_runner_args
      Deadfinder::Runner.new.run("http://once.test/", options, **args)

      # One status check for the link pass plus one body read for the anchor
      # pass — not one per fragment.
      requests.should eq 2
      args[:output]["http://once.test/"].sort.should eq [
        "http://once.test/guide#nope1",
        "http://once.test/guide#nope2",
      ]
    end

    it "leaves a fragment on a non-HTML document alone" do
      WebMock.stub(:get, "http://pdf.test/")
        .to_return(body: %(<html><body><a href="/manual.pdf#page=3">p</a></body></html>))
      WebMock.stub(:get, "http://pdf.test/manual.pdf")
        .to_return(status: 200, body: "%PDF-1.4", headers: {"Content-Type" => "application/pdf"})

      options = default_test_options
      options.check_anchors = true
      args = make_runner_args
      Deadfinder::Runner.new.run("http://pdf.test/", options, **args)

      (args[:output]["http://pdf.test/"]? || [] of String).should be_empty
    end

    it "does not re-report a fragment whose document already failed the HTTP check" do
      WebMock.stub(:get, "http://gone.test/")
        .to_return(body: %(<html><body><a href="/guide#nope">n</a></body></html>))
      WebMock.stub(:get, "http://gone.test/guide").to_return(status: 404)

      options = default_test_options
      options.check_anchors = true
      args = make_runner_args
      Deadfinder::Runner.new.run("http://gone.test/", options, **args)

      # Reported exactly once, as the HTTP failure it is.
      args[:output]["http://gone.test/"].should eq ["http://gone.test/guide#nope"]
    end

    it "counts a missing anchor as dead in coverage" do
      html = %(<html><body>
        <a href="/guide#install">a</a>
        <a href="/guide#nope">b</a>
      </body></html>)
      WebMock.stub(:get, "http://cov.test/").to_return(body: html)
      WebMock.stub(:get, "http://cov.test/guide")
        .to_return(status: 200, body: doc, headers: {"Content-Type" => "text/html"})

      options = default_test_options
      options.check_anchors = true
      options.coverage = true
      args = make_runner_args
      Deadfinder::Runner.new.run("http://cov.test/", options, **args)

      cov = args[:coverage_data]["http://cov.test/"]
      cov.total.should eq 2
      cov.dead.should eq 1
      # The HTTP histogram still reports what the server actually answered.
      cov.status_counts["200"].should eq 2
    end
  end
end
