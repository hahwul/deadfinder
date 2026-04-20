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
  end

  describe "#worker" do
    it "detects 404 as broken link" do
      target = "http://example.com"
      url = "http://example.com/broken"

      WebMock.stub(:get, url).to_return(status: 404)

      runner = Deadfinder::Runner.new
      options = default_test_options
      args = make_runner_args

      jobs = Channel(String).new(10)
      results = Channel(String).new(10)
      jobs.send(url)
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

      jobs = Channel(String).new(10)
      results = Channel(String).new(10)
      jobs.send(url)
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

      jobs = Channel(String).new(10)
      results = Channel(String).new(10)
      jobs.send(url)
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

      jobs = Channel(String).new(10)
      results = Channel(String).new(10)
      jobs.send(url)
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

      jobs = Channel(String).new(10)
      results = Channel(String).new(10)
      jobs.send(url)
      jobs.close

      runner.worker(1, jobs, results, target, options, **args)

      args[:output][target].should contain url
    end

    it "skips already cached URLs" do
      target = "http://example.com"
      url = "http://example.com/cached"

      WebMock.stub(:get, url).to_return(status: 404)

      runner = Deadfinder::Runner.new
      options = default_test_options
      args = make_runner_args
      # Pre-populate cache
      args[:cache_set][url] = true

      jobs = Channel(String).new(10)
      results = Channel(String).new(10)
      jobs.send(url)
      jobs.close

      runner.worker(1, jobs, results, target, options, **args)

      # Should NOT appear in output because it was cached
      (args[:output][target]? || [] of String).should_not contain url
    end

    it "processes multiple jobs sequentially" do
      target = "http://example.com"

      WebMock.stub(:get, "http://example.com/a").to_return(status: 404)
      WebMock.stub(:get, "http://example.com/b").to_return(status: 200)
      WebMock.stub(:get, "http://example.com/c").to_return(status: 503)

      runner = Deadfinder::Runner.new
      options = default_test_options
      args = make_runner_args

      jobs = Channel(String).new(10)
      results = Channel(String).new(10)
      jobs.send("http://example.com/a")
      jobs.send("http://example.com/b")
      jobs.send("http://example.com/c")
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

      jobs = Channel(String).new(10)
      results = Channel(String).new(10)
      jobs.send("http://example.com/ok")
      jobs.send("http://example.com/not-found")
      jobs.send("http://example.com/server-err")
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

      jobs = Channel(String).new(10)
      results = Channel(String).new(10)
      jobs.send(url)
      jobs.close

      runner.worker(1, jobs, results, target, options, **args)

      # Should not be in dead links (200 response with correct headers)
      (args[:output][target]? || [] of String).should_not contain url
    end
  end
end
