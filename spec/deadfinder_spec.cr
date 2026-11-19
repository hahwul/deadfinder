require "./spec_helper"

describe Deadfinder do
  before_each do
    WebMock.reset
    reset_deadfinder_state
  end

  describe "#version" do
    it "returns the version number" do
      Deadfinder::VERSION.should_not be_nil
      Deadfinder::VERSION.should eq "2.1.0"
    end
  end

  describe ".reset_state" do
    it "clears output, coverage_data, and status_cache accumulators" do
      Deadfinder.output["foo"] = ["bar"]
      Deadfinder.coverage_data["foo"] = Deadfinder::TargetCoverage.new(total: 1, dead: 1)
      Deadfinder.status_cache["foo"] = 200

      Deadfinder.reset_state

      Deadfinder.output.should be_empty
      Deadfinder.coverage_data.should be_empty
      Deadfinder.status_cache.should be_empty
    end

    it "clears a recorded I/O failure" do
      Deadfinder.io_error "simulated by the spec"
      Deadfinder.io_failed?.should be_true

      Deadfinder.reset_state

      Deadfinder.io_failed?.should be_false
    end
  end

  describe "#run_url" do
    it "scans a single URL and collects broken links" do
      target = "http://mock-site.test"
      html = <<-HTML
        <html><body>
          <a href="http://mock-site.test/dead">Dead</a>
          <a href="http://mock-site.test/alive">Alive</a>
        </body></html>
      HTML

      WebMock.stub(:get, target).to_return(body: html)
      WebMock.stub(:get, "http://mock-site.test/dead").to_return(status: 404)
      WebMock.stub(:get, "http://mock-site.test/alive").to_return(status: 200)

      options = default_test_options
      Deadfinder.run_url(target, options)

      Deadfinder.output[target]?.should_not be_nil
      Deadfinder.output[target].should contain "http://mock-site.test/dead"
      Deadfinder.output[target].should_not contain "http://mock-site.test/alive"
    end

    it "writes JSON output to file when output is specified" do
      target = "http://mock-site.test"
      html = %(<html><body><a href="http://mock-site.test/broken">X</a></body></html>)

      WebMock.stub(:get, target).to_return(body: html)
      WebMock.stub(:get, "http://mock-site.test/broken").to_return(status: 404)

      tempfile = File.tempfile("deadfinder_run_url", ".json")
      begin
        options = default_test_options
        options.output = tempfile.path
        options.output_format = "json"

        Deadfinder.run_url(target, options)

        content = File.read(tempfile.path)
        parsed = JSON.parse(content)
        parsed[target].as_a.map(&.as_s).should contain "http://mock-site.test/broken"
      ensure
        tempfile.delete
      end
    end
    it "reports a scheme-less target instead of scanning" do
      Deadfinder.run_url("bad.test/index.html", default_test_options)
      Deadfinder.output.should be_empty
    end
  end

  describe "#run_file" do
    it "scans URLs read from a file" do
      target = "http://mock-file.test"
      html = %(<html><body><a href="http://mock-file.test/dead">X</a></body></html>)

      WebMock.stub(:get, target).to_return(body: html)
      WebMock.stub(:get, "http://mock-file.test/dead").to_return(status: 404)

      urlfile = File.tempfile("deadfinder_urls", ".txt")
      begin
        File.write(urlfile.path, "#{target}\n")

        options = default_test_options
        Deadfinder.run_file(urlfile.path, options)

        Deadfinder.output[target]?.should_not be_nil
        Deadfinder.output[target].should contain "http://mock-file.test/dead"
      ensure
        urlfile.delete
      end
    end

    it "respects limit option" do
      html1 = %(<html><body><a href="http://mock1.test/page">P</a></body></html>)
      html2 = %(<html><body><a href="http://mock2.test/page">P</a></body></html>)

      WebMock.stub(:get, "http://mock1.test").to_return(body: html1)
      WebMock.stub(:get, "http://mock1.test/page").to_return(status: 200)
      WebMock.stub(:get, "http://mock2.test").to_return(body: html2)
      WebMock.stub(:get, "http://mock2.test/page").to_return(status: 200)

      urlfile = File.tempfile("deadfinder_urls", ".txt")
      begin
        File.write(urlfile.path, "http://mock1.test\nhttp://mock2.test\n")

        options = default_test_options
        options.limit = 1

        Deadfinder.run_file(urlfile.path, options)

        # Only the first URL should be scanned
        Deadfinder.output.keys.size.should be <= 1
      ensure
        urlfile.delete
      end
    end

    it "does not crash when the input file cannot be read" do
      # No file at this path -> File.read_lines raises IO::Error, which must be
      # handled gracefully (scan nothing) rather than crash with a stack trace.
      missing = File.join(Dir.tempdir, "deadfinder_missing_#{Time.utc.to_unix_ns}.txt")

      options = default_test_options
      Deadfinder.run_file(missing, options)

      Deadfinder.output.should be_empty
    end

    it "records an unreadable input file as an I/O failure" do
      # Scanning nothing must not look like a clean scan: the CLI exits 1 on this.
      missing = File.join(Dir.tempdir, "deadfinder_missing_#{Time.utc.to_unix_ns}.txt")

      Deadfinder.run_file(missing, default_test_options)

      Deadfinder.io_failed?.should be_true
    end

    it "does not double-count coverage when a target is listed more than once" do
      target = "http://dup-target.test"
      html = %(<html><body><a href="http://dup-target.test/dead">d</a></body></html>)
      WebMock.stub(:get, target).to_return(body: html)
      WebMock.stub(:get, "http://dup-target.test/dead").to_return(status: 404)

      urlfile = File.tempfile("deadfinder_dups", ".txt")
      begin
        File.write(urlfile.path, "#{target}\n#{target}\n")

        options = default_test_options
        options.coverage = true
        Deadfinder.run_file(urlfile.path, options)

        cov = Deadfinder.coverage_data[target]
        cov.total.should eq 1
        cov.dead.should eq 1
        Deadfinder.output[target].count("http://dup-target.test/dead").should eq 1
      ensure
        urlfile.delete
      end
    end

    it "skips blank lines, whitespace padding and # comments" do
      target = "http://mock-blank.test"
      html = %(<html><body><a href="http://mock-blank.test/dead">X</a></body></html>)

      WebMock.stub(:get, target).to_return(body: html)
      WebMock.stub(:get, "http://mock-blank.test/dead").to_return(status: 404)

      urlfile = File.tempfile("deadfinder_blank", ".txt")
      begin
        File.write(urlfile.path, "\n   \n# a comment\n  #{target}  \n\n")

        options = default_test_options
        Deadfinder.run_file(urlfile.path, options)

        # Padding is trimmed, so the report is keyed by the clean URL and the
        # blank/comment lines never became (failing) targets of their own.
        Deadfinder.output.keys.should eq [target]
        Deadfinder.output[target].should contain "http://mock-blank.test/dead"
      ensure
        urlfile.delete
      end
    end

    it "strips a leading UTF-8 BOM from the first line" do
      target = "http://mock-bom.test"
      html = %(<html><body><a href="http://mock-bom.test/dead">X</a></body></html>)

      WebMock.stub(:get, target).to_return(body: html)
      WebMock.stub(:get, "http://mock-bom.test/dead").to_return(status: 404)

      urlfile = File.tempfile("deadfinder_bom", ".txt")
      begin
        File.write(urlfile.path, "#{Deadfinder::UTF8_BOM}#{target}\n")

        options = default_test_options
        Deadfinder.run_file(urlfile.path, options)

        Deadfinder.output.keys.should eq [target]
      ensure
        urlfile.delete
      end
    end

    it "counts only real targets against limit" do
      html1 = %(<html><body><a href="http://lim1.test/page">P</a></body></html>)
      html2 = %(<html><body><a href="http://lim2.test/page">P</a></body></html>)

      WebMock.stub(:get, "http://lim1.test").to_return(body: html1)
      WebMock.stub(:get, "http://lim1.test/page").to_return(status: 404)
      WebMock.stub(:get, "http://lim2.test").to_return(body: html2)
      WebMock.stub(:get, "http://lim2.test/page").to_return(status: 404)

      urlfile = File.tempfile("deadfinder_limit_blank", ".txt")
      begin
        # Blank lines between the two targets used to consume the limit, so
        # `--limit 2` scanned only the first URL.
        File.write(urlfile.path, "http://lim1.test\n\n\nhttp://lim2.test\n")

        options = default_test_options
        options.limit = 2
        Deadfinder.run_file(urlfile.path, options)

        Deadfinder.output.keys.sort.should eq ["http://lim1.test", "http://lim2.test"]
      ensure
        urlfile.delete
      end
    end

    it "skips targets that are not absolute http(s) URLs" do
      urlfile = File.tempfile("deadfinder_invalid", ".txt")
      begin
        # A bare domain has no host once parsed, `file://` parses to an empty
        # host, and a non-http scheme would otherwise be fetched as plain HTTP.
        File.write(urlfile.path, "example.com\nfile:///etc/hosts\nftp://example.com/a\n")

        options = default_test_options
        Deadfinder.run_file(urlfile.path, options)

        Deadfinder.output.should be_empty
      ensure
        urlfile.delete
      end
    end
  end

  describe "target-level concurrency" do
    it "scans several targets at once" do
      pages_inflight = 0
      pages_peak = 0

      WebMock.stub(:get, /http:\/\/conc\.test\/page\/\d+/).to_return do |request|
        pages_inflight += 1
        pages_peak = pages_inflight if pages_inflight > pages_peak
        sleep 5.milliseconds
        pages_inflight -= 1
        n = request.resource.split('/').last
        HTTP::Client::Response.new(200,
          body: %(<html><body><a href="http://conc.test/dead/#{n}">d</a></body></html>))
      end
      WebMock.stub(:get, /http:\/\/conc\.test\/dead\/\d+/).to_return(status: 404)

      urlfile = File.tempfile("deadfinder_tc", ".txt")
      begin
        File.write(urlfile.path, (0...4).map { |n| "http://conc.test/page/#{n}" }.join('\n'))

        options = default_test_options
        options.concurrency = 8
        options.target_concurrency = 4
        Deadfinder.run_file(urlfile.path, options)

        pages_peak.should eq 4
        Deadfinder.output.keys.size.should eq 4
        Deadfinder.output["http://conc.test/page/2"].should eq ["http://conc.test/dead/2"]
      ensure
        urlfile.delete
      end
    end

    it "scans strictly one target at a time with --target-concurrency 1" do
      pages_inflight = 0
      pages_peak = 0

      WebMock.stub(:get, /http:\/\/serial\.test\/page\/\d+/).to_return do |request|
        pages_inflight += 1
        pages_peak = pages_inflight if pages_inflight > pages_peak
        sleep 2.milliseconds
        pages_inflight -= 1
        n = request.resource.split('/').last
        HTTP::Client::Response.new(200,
          body: %(<html><body><a href="http://serial.test/dead/#{n}">d</a></body></html>))
      end
      WebMock.stub(:get, /http:\/\/serial\.test\/dead\/\d+/).to_return(status: 404)

      urlfile = File.tempfile("deadfinder_tc1", ".txt")
      begin
        File.write(urlfile.path, (0...4).map { |n| "http://serial.test/page/#{n}" }.join('\n'))

        options = default_test_options
        options.target_concurrency = 1
        Deadfinder.run_file(urlfile.path, options)

        pages_peak.should eq 1
        Deadfinder.output.keys.size.should eq 4
      ensure
        urlfile.delete
      end
    end

    it "caps total in-flight requests at --concurrency however many targets run" do
      inflight = 0
      peak = 0

      # One stub for pages and links alike: the budget covers every request the
      # run makes, not just the link checks.
      WebMock.stub(:get, /http:\/\/cap\.test\//).to_return do |request|
        inflight += 1
        peak = inflight if inflight > peak
        sleep 2.milliseconds
        inflight -= 1

        if request.resource.starts_with?("/page/")
          n = request.resource.split('/').last
          links = String.build do |io|
            3.times { |i| io << %(<a href="http://cap.test/link/#{n}/#{i}">l</a>) }
          end
          HTTP::Client::Response.new(200, body: "<html><body>#{links}</body></html>")
        else
          HTTP::Client::Response.new(200, body: "ok")
        end
      end

      urlfile = File.tempfile("deadfinder_cap", ".txt")
      begin
        File.write(urlfile.path, (0...6).map { |n| "http://cap.test/page/#{n}" }.join('\n'))

        options = default_test_options
        # Six targets x four workers each would be 24 sockets without a global
        # budget; `-c 2` has to hold regardless of the target concurrency.
        options.concurrency = 2
        options.target_concurrency = 6
        Deadfinder.run_file(urlfile.path, options)

        peak.should eq 2
        inflight.should eq 0
      ensure
        urlfile.delete
      end
    end

    it "serializes the report in the requested order even when targets finish out of order" do
      # Later targets answer faster, so completion order is the reverse of the
      # input order; the report must still follow the file.
      WebMock.stub(:get, /http:\/\/order\.test\/page\/\d+/).to_return do |request|
        n = request.resource.split('/').last.to_i
        sleep ((4 - n) * 5).milliseconds
        HTTP::Client::Response.new(200,
          body: %(<html><body><a href="http://order.test/dead/#{n}">d</a></body></html>))
      end
      WebMock.stub(:get, /http:\/\/order\.test\/dead\/\d+/).to_return(status: 404)

      urlfile = File.tempfile("deadfinder_order", ".txt")
      report = File.tempfile("deadfinder_order_report", ".json")
      begin
        targets = (0...4).map { |n| "http://order.test/page/#{n}" }
        File.write(urlfile.path, targets.join('\n'))

        options = default_test_options
        options.coverage = true
        options.target_concurrency = 4
        options.output = report.path
        Deadfinder.run_file(urlfile.path, options)

        # The accumulator is filled in completion order, which is racy by
        # nature; the serialized report is the contract, and it follows the
        # order the targets were asked for.
        Deadfinder.output.keys.sort.should eq targets
        parsed = JSON.parse(File.read(report.path))
        parsed["dead_links"].as_h.keys.should eq targets
        parsed["coverage"]["targets"].as_h.keys.should eq targets
      ensure
        urlfile.delete
        report.delete
      end
    end

    it "still honors --limit when targets are scanned concurrently" do
      WebMock.stub(:get, /http:\/\/lim\.test\/page\/\d+/).to_return do |request|
        n = request.resource.split('/').last
        HTTP::Client::Response.new(200,
          body: %(<html><body><a href="http://lim.test/dead/#{n}">d</a></body></html>))
      end
      WebMock.stub(:get, /http:\/\/lim\.test\/dead\/\d+/).to_return(status: 404)

      urlfile = File.tempfile("deadfinder_tclimit", ".txt")
      begin
        File.write(urlfile.path, (0...6).map { |n| "http://lim.test/page/#{n}" }.join('\n'))

        options = default_test_options
        options.target_concurrency = 6
        options.limit = 2
        Deadfinder.run_file(urlfile.path, options)

        Deadfinder.output.keys.should eq [
          "http://lim.test/page/0",
          "http://lim.test/page/1",
        ]
      ensure
        urlfile.delete
      end
    end
  end

  describe ".read_targets" do
    it "normalizes, dedupes and preserves first-seen order" do
      io = IO::Memory.new(<<-LIST)
        #{Deadfinder::UTF8_BOM}http://a.test

          http://b.test\t
        # http://commented.test
        http://a.test
        LIST

      Deadfinder.read_targets(io, 0).should eq ["http://a.test", "http://b.test"]
    end

    it "handles CRLF line endings" do
      io = IO::Memory.new("http://a.test\r\nhttp://b.test\r\n")
      Deadfinder.read_targets(io, 0).should eq ["http://a.test", "http://b.test"]
    end

    it "rejects targets that cannot be fetched over http(s)" do
      Deadfinder::Logger.silent = true
      io = IO::Memory.new("example.com\nfile:///etc/hosts\nftp://x.test/a\n://broken\n")
      Deadfinder.read_targets(io, 0).should be_empty
    end

    it "stops reading as soon as the limit is reached" do
      # A still-open stream: without an early break the read would block here
      # instead of returning the single target the limit asked for.
      reader, writer = IO.pipe
      begin
        writer.puts "http://a.test"
        writer.puts "http://b.test"
        Deadfinder.read_targets(reader, 1).should eq ["http://a.test"]
      ensure
        writer.close
        reader.close
      end
    end

    it "counts only valid targets against the limit" do
      io = IO::Memory.new("\n# c\nhttp://a.test\n\nhttp://b.test\n")
      Deadfinder.read_targets(io, 2).should eq ["http://a.test", "http://b.test"]
    end
  end

  describe "#run_sitemap" do
    it "parses sitemap XML and scans discovered URLs" do
      sitemap_xml = <<-XML
        <?xml version="1.0" encoding="UTF-8"?>
        <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
          <url><loc>http://mock-sitemap.test/page1</loc></url>
          <url><loc>http://mock-sitemap.test/page2</loc></url>
        </urlset>
      XML

      html1 = %(<html><body><a href="http://mock-sitemap.test/dead1">D</a></body></html>)
      html2 = %(<html><body><a href="http://mock-sitemap.test/ok">O</a></body></html>)

      WebMock.stub(:get, "http://mock-sitemap.test/sitemap.xml").to_return(body: sitemap_xml)
      WebMock.stub(:get, "http://mock-sitemap.test/page1").to_return(body: html1)
      WebMock.stub(:get, "http://mock-sitemap.test/page2").to_return(body: html2)
      WebMock.stub(:get, "http://mock-sitemap.test/dead1").to_return(status: 404)
      WebMock.stub(:get, "http://mock-sitemap.test/ok").to_return(status: 200)

      options = default_test_options
      Deadfinder.run_sitemap("http://mock-sitemap.test/sitemap.xml", options)

      Deadfinder.output["http://mock-sitemap.test/page1"]?.should_not be_nil
      Deadfinder.output["http://mock-sitemap.test/page1"].should contain "http://mock-sitemap.test/dead1"
    end

    it "terminates on a cyclic sitemap index without infinite recursion" do
      # a.xml references b.xml, b.xml references a.xml — must not loop.
      sitemap_a = <<-XML
        <?xml version="1.0" encoding="UTF-8"?>
        <sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
          <sitemap><loc>http://cycle.test/b.xml</loc></sitemap>
        </sitemapindex>
      XML
      sitemap_b = <<-XML
        <?xml version="1.0" encoding="UTF-8"?>
        <sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
          <sitemap><loc>http://cycle.test/a.xml</loc></sitemap>
        </sitemapindex>
      XML

      WebMock.stub(:get, "http://cycle.test/a.xml").to_return(body: sitemap_a)
      WebMock.stub(:get, "http://cycle.test/b.xml").to_return(body: sitemap_b)

      options = default_test_options
      # Should return cleanly (no stack overflow, no hang).
      Deadfinder.run_sitemap("http://cycle.test/a.xml", options)
      Deadfinder.output.should be_empty
    end

    it "parses sitemap without namespace" do
      sitemap_xml = <<-XML
        <?xml version="1.0" encoding="UTF-8"?>
        <urlset>
          <url><loc>http://mock-sitemap2.test/page1</loc></url>
        </urlset>
      XML

      html = %(<html><body><a href="http://mock-sitemap2.test/broken">B</a></body></html>)

      WebMock.stub(:get, "http://mock-sitemap2.test/sitemap.xml").to_return(body: sitemap_xml)
      WebMock.stub(:get, "http://mock-sitemap2.test/page1").to_return(body: html)
      WebMock.stub(:get, "http://mock-sitemap2.test/broken").to_return(status: 404)

      options = default_test_options
      Deadfinder.run_sitemap("http://mock-sitemap2.test/sitemap.xml", options)

      Deadfinder.output["http://mock-sitemap2.test/page1"]?.should_not be_nil
      Deadfinder.output["http://mock-sitemap2.test/page1"].should contain "http://mock-sitemap2.test/broken"
    end

    it "does not scan child sitemap files as page targets (sitemap index)" do
      index_xml = <<-XML
        <?xml version="1.0" encoding="UTF-8"?>
        <sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
          <sitemap><loc>http://idx.test/sub.xml</loc></sitemap>
        </sitemapindex>
      XML
      sub_xml = <<-XML
        <?xml version="1.0" encoding="UTF-8"?>
        <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
          <url><loc>http://idx.test/page1</loc></url>
        </urlset>
      XML

      WebMock.stub(:get, "http://idx.test/index.xml").to_return(body: index_xml)

      sub_fetch = 0
      WebMock.stub(:get, "http://idx.test/sub.xml").to_return do
        sub_fetch += 1
        HTTP::Client::Response.new(200, sub_xml)
      end

      WebMock.stub(:get, "http://idx.test/page1").to_return(body: %(<html><body><a href="http://idx.test/dead">d</a></body></html>))
      WebMock.stub(:get, "http://idx.test/dead").to_return(status: 404)

      options = default_test_options
      Deadfinder.run_sitemap("http://idx.test/index.xml", options)

      # sub.xml is fetched once (to recurse into it), never scanned as a page.
      sub_fetch.should eq 1
      Deadfinder.output["http://idx.test/sub.xml"]?.should be_nil
      Deadfinder.output["http://idx.test/page1"]?.should_not be_nil
      Deadfinder.output["http://idx.test/page1"].should contain "http://idx.test/dead"
    end

    it "follows a redirect to the real sitemap document" do
      sitemap_xml = <<-XML
        <?xml version="1.0" encoding="UTF-8"?>
        <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
          <url><loc>http://sm-redirect.test/page1</loc></url>
        </urlset>
      XML

      WebMock.stub(:get, "http://sm-redirect.test/sitemap.xml")
        .to_return(status: 301, headers: {"Location" => "/sitemap_index.xml"})
      WebMock.stub(:get, "http://sm-redirect.test/sitemap_index.xml").to_return(body: sitemap_xml)
      WebMock.stub(:get, "http://sm-redirect.test/page1")
        .to_return(body: %(<html><body><a href="http://sm-redirect.test/dead">d</a></body></html>))
      WebMock.stub(:get, "http://sm-redirect.test/dead").to_return(status: 404)

      Deadfinder.run_sitemap("http://sm-redirect.test/sitemap.xml", default_test_options)

      Deadfinder.output["http://sm-redirect.test/page1"].should contain "http://sm-redirect.test/dead"
    end

    it "resolves relative <loc> values against the sitemap location" do
      sitemap_xml = <<-XML
        <?xml version="1.0" encoding="UTF-8"?>
        <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
          <url><loc>/page1</loc></url>
        </urlset>
      XML

      WebMock.stub(:get, "http://sm-rel.test/sitemap.xml").to_return(body: sitemap_xml)
      WebMock.stub(:get, "http://sm-rel.test/page1")
        .to_return(body: %(<html><body><a href="http://sm-rel.test/dead">d</a></body></html>))
      WebMock.stub(:get, "http://sm-rel.test/dead").to_return(status: 404)

      Deadfinder.run_sitemap("http://sm-rel.test/sitemap.xml", default_test_options)

      Deadfinder.output["http://sm-rel.test/page1"].should contain "http://sm-rel.test/dead"
    end

    it "resolves a relative child sitemap in a sitemap index" do
      index_xml = <<-XML
        <?xml version="1.0" encoding="UTF-8"?>
        <sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
          <sitemap><loc>/sub.xml</loc></sitemap>
        </sitemapindex>
      XML
      sub_xml = <<-XML
        <?xml version="1.0" encoding="UTF-8"?>
        <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
          <url><loc>http://sm-relidx.test/page1</loc></url>
        </urlset>
      XML

      WebMock.stub(:get, "http://sm-relidx.test/index.xml").to_return(body: index_xml)
      WebMock.stub(:get, "http://sm-relidx.test/sub.xml").to_return(body: sub_xml)
      WebMock.stub(:get, "http://sm-relidx.test/page1")
        .to_return(body: %(<html><body><a href="http://sm-relidx.test/dead">d</a></body></html>))
      WebMock.stub(:get, "http://sm-relidx.test/dead").to_return(status: 404)

      Deadfinder.run_sitemap("http://sm-relidx.test/index.xml", default_test_options)

      Deadfinder.output["http://sm-relidx.test/page1"].should contain "http://sm-relidx.test/dead"
    end

    it "parses a gzip-compressed sitemap body" do
      sitemap_xml = <<-XML
        <?xml version="1.0" encoding="UTF-8"?>
        <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
          <url><loc>http://sm-gz.test/page1</loc></url>
        </urlset>
      XML
      io = IO::Memory.new
      Compress::Gzip::Writer.open(io) { |gz| gz.print sitemap_xml }

      WebMock.stub(:get, "http://sm-gz.test/sitemap.xml.gz").to_return(body: String.new(io.to_slice))
      WebMock.stub(:get, "http://sm-gz.test/page1")
        .to_return(body: %(<html><body><a href="http://sm-gz.test/dead">d</a></body></html>))
      WebMock.stub(:get, "http://sm-gz.test/dead").to_return(status: 404)

      Deadfinder.run_sitemap("http://sm-gz.test/sitemap.xml.gz", default_test_options)

      Deadfinder.output["http://sm-gz.test/page1"].should contain "http://sm-gz.test/dead"
    end

    it "stops downloading child sitemaps once --limit is satisfied" do
      index_xml = String.build do |io|
        io << %(<?xml version="1.0" encoding="UTF-8"?>)
        io << %(<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">)
        3.times { |i| io << "<sitemap><loc>http://sm-limit.test/sub#{i}.xml</loc></sitemap>" }
        io << "</sitemapindex>"
      end

      WebMock.stub(:get, "http://sm-limit.test/index.xml").to_return(body: index_xml)
      fetched = [] of String
      3.times do |i|
        WebMock.stub(:get, "http://sm-limit.test/sub#{i}.xml").to_return do
          fetched << "sub#{i}"
          HTTP::Client::Response.new(200, body: %(<urlset><url><loc>http://sm-limit.test/page#{i}</loc></url></urlset>))
        end
        WebMock.stub(:get, "http://sm-limit.test/page#{i}").to_return(body: "<html></html>")
      end

      options = default_test_options
      options.limit = 1
      Deadfinder.run_sitemap("http://sm-limit.test/index.xml", options)

      fetched.should eq ["sub0"]
    end

    it "reports a scheme-less sitemap target instead of scanning" do
      Deadfinder.run_sitemap("sm-bad.test/sitemap.xml", default_test_options)
      Deadfinder.output.should be_empty
    end

    it "parses a sitemap using the legacy Google 0.84 namespace" do
      sitemap_xml = <<-XML
        <?xml version="1.0" encoding="UTF-8"?>
        <urlset xmlns="http://www.google.com/schemas/sitemap/0.84">
          <url><loc>http://legacy.test/page1</loc></url>
        </urlset>
      XML

      WebMock.stub(:get, "http://legacy.test/sitemap.xml").to_return(body: sitemap_xml)
      WebMock.stub(:get, "http://legacy.test/page1").to_return(body: %(<html><body><a href="http://legacy.test/dead">d</a></body></html>))
      WebMock.stub(:get, "http://legacy.test/dead").to_return(status: 404)

      options = default_test_options
      Deadfinder.run_sitemap("http://legacy.test/sitemap.xml", options)

      Deadfinder.output["http://legacy.test/page1"]?.should_not be_nil
      Deadfinder.output["http://legacy.test/page1"].should contain "http://legacy.test/dead"
    end

    it "keeps a raw & in <loc> instead of the URL libxml2 recovers" do
      # Not well-formed: the first <loc> has an unescaped ampersand, which
      # libxml2 recovers as `/search?q=ok=2`, and every `&amp;` after it as
      # nothing. The other entries pin down what the repair must keep: an
      # escaped ampersand, hex and decimal character references, and a CDATA
      # section, where `&` is literal. (No XML declaration: the heredoc indents
      # it, which is an error of its own.)
      sitemap_xml = <<-XML
        <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
          <url><loc>http://sm-amp.test/search?q=ok&page=2</loc></url>
          <url><loc>http://sm-amp.test/search?q=ok&amp;page=3</loc></url>
          <url><loc>http://sm-amp.test/search?q=ok&#x26;page=4</loc></url>
          <url><loc><![CDATA[http://sm-amp.test/search?q=ok&page=5]]></loc></url>
          <url><loc>http://sm-amp.test/search?q=ok&#38;page=6</loc></url>
        </urlset>
      XML

      pages = (2..6).map { |n| "http://sm-amp.test/search?q=ok&page=#{n}" }
      WebMock.stub(:get, "http://sm-amp.test/sitemap.xml").to_return(body: sitemap_xml)
      pages.each do |page|
        WebMock.stub(:get, page).to_return(body: %(<html><body><a href="http://sm-amp.test/dead">d</a></body></html>))
      end
      WebMock.stub(:get, "http://sm-amp.test/dead").to_return(status: 404)

      log = IO::Memory.new
      Deadfinder::Logger.sink = log
      options = default_test_options
      options.silent = false
      Deadfinder.run_sitemap("http://sm-amp.test/sitemap.xml", options)

      Deadfinder.output.keys.sort.should eq pages
      Deadfinder.dead_targets.should be_empty
      # Repaired cleanly, so there is nothing left to warn about.
      log.to_s.should_not contain "not well-formed"
    end

    it "keeps &amp; in <loc> when the sitemap has an error the repair cannot fix" do
      # Whitespace before the XML declaration is an error too, after which
      # libxml2 drops every `&amp;`: `?q=ok&amp;page=2` became `?q=okpage=2`.
      sitemap = "http://sm-ws.test/sitemap.xml"
      page = "http://sm-ws.test/search?q=ok&page=2"
      WebMock.stub(:get, sitemap)
        .to_return(body: %(\n<?xml version="1.0"?><urlset><url><loc>http://sm-ws.test/search?q=ok&amp;page=2</loc></url></urlset>))
      WebMock.stub(:get, page).to_return(body: %(<html><body><a href="http://sm-ws.test/dead">d</a></body></html>))
      WebMock.stub(:get, "http://sm-ws.test/dead").to_return(status: 404)

      log = IO::Memory.new
      Deadfinder::Logger.sink = log
      options = default_test_options
      options.silent = false
      Deadfinder.run_sitemap(sitemap, options)

      Deadfinder.output.keys.should eq [page]
      Deadfinder.dead_targets.should be_empty
      log.to_s.should contain "Sitemap #{sitemap} is not well-formed XML"
    end

    it "says so when a sitemap is not well-formed, and still scans what was recovered" do
      # Cut off mid-<loc>, as by an interrupted upload or a generator that died.
      sitemap = "http://sm-trunc.test/sitemap.xml"
      WebMock.stub(:get, sitemap)
        .to_return(body: %(<urlset><url><loc>http://sm-trunc.test/page1</loc></url><url><loc>http://sm-trunc.test/pag))
      WebMock.stub(:get, "http://sm-trunc.test/page1")
        .to_return(body: %(<html><body><a href="http://sm-trunc.test/dead">d</a></body></html>))
      WebMock.stub(:get, "http://sm-trunc.test/pag").to_return(status: 404)
      WebMock.stub(:get, "http://sm-trunc.test/dead").to_return(status: 404)

      log = IO::Memory.new
      Deadfinder::Logger.sink = log
      options = default_test_options
      options.silent = false
      Deadfinder.run_sitemap(sitemap, options)

      log.to_s.scan("Sitemap #{sitemap} is not well-formed XML").size.should eq 1
      Deadfinder.output["http://sm-trunc.test/page1"].should contain "http://sm-trunc.test/dead"
      Deadfinder.dead_targets.has_key?(sitemap).should be_false
    end

    it "records a 200 that is not a sitemap as a dead target" do
      # A soft 404 page, a page that happens to parse cleanly as XML, and an
      # empty body: each used to yield zero URLs and a clean exit.
      bodies = {
        "html"  => %(<!doctype html><html><head><title>Not found</title></head><body><br><a href="/x">x</a></body></html>),
        "xhtml" => %(<html><body><p>Not found</p></body></html>),
        "empty" => "",
      }
      bodies.each do |name, body|
        sitemap = "http://sm-not-#{name}.test/sitemap.xml"
        WebMock.stub(:get, sitemap).to_return(body: body)

        Deadfinder.run_sitemap(sitemap, default_test_options)

        Deadfinder.dead_targets[sitemap]?.should eq "error"
      end
      Deadfinder.output.should be_empty
    end

    it "treats an empty <urlset/> as a clean result, not a dead sitemap" do
      WebMock.stub(:get, "http://sm-empty.test/sitemap.xml")
        .to_return(body: %(<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"/>))

      Deadfinder.run_sitemap("http://sm-empty.test/sitemap.xml", default_test_options)

      Deadfinder.dead_targets.should be_empty
      Deadfinder.output.should be_empty
    end

    it "does not call a sitemap with a relative xmlns URI malformed" do
      # Well-formed, but libxml2 reports the namespace warning as an error.
      WebMock.stub(:get, "http://sm-relns.test/sitemap.xml")
        .to_return(body: %(<urlset xmlns="sitemaps.org/0.9"><url><loc>http://sm-relns.test/page1</loc></url></urlset>))
      WebMock.stub(:get, "http://sm-relns.test/page1")
        .to_return(body: %(<html><body><a href="http://sm-relns.test/dead">d</a></body></html>))
      WebMock.stub(:get, "http://sm-relns.test/dead").to_return(status: 404)

      log = IO::Memory.new
      Deadfinder::Logger.sink = log
      options = default_test_options
      options.silent = false
      Deadfinder.run_sitemap("http://sm-relns.test/sitemap.xml", options)

      log.to_s.should_not contain "not well-formed"
      Deadfinder.output["http://sm-relns.test/page1"].should contain "http://sm-relns.test/dead"
    end

    it "does not scan <image:loc> entries when a urlset only repeats known pages" do
      # b.xml adds no new page, which used to look like "matched neither a
      # urlset nor an index" and sent it through the top-level <loc> fallback.
      index_xml = <<-XML
        <sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
          <sitemap><loc>http://sm-dupe.test/a.xml</loc></sitemap>
          <sitemap><loc>http://sm-dupe.test/b.xml</loc></sitemap>
        </sitemapindex>
      XML
      a_xml = %(<urlset><url><loc>http://sm-dupe.test/page1</loc></url></urlset>)
      b_xml = <<-XML
        <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:image="http://www.google.com/schemas/sitemap-image/1.1">
          <url>
            <loc>http://sm-dupe.test/page1</loc>
            <image:image><image:loc>http://sm-dupe.test/photo.png</image:loc></image:image>
          </url>
        </urlset>
      XML

      WebMock.stub(:get, "http://sm-dupe.test/index.xml").to_return(body: index_xml)
      WebMock.stub(:get, "http://sm-dupe.test/a.xml").to_return(body: a_xml)
      WebMock.stub(:get, "http://sm-dupe.test/b.xml").to_return(body: b_xml)
      WebMock.stub(:get, "http://sm-dupe.test/page1").to_return(body: "<html></html>")
      image_fetches = 0
      WebMock.stub(:get, "http://sm-dupe.test/photo.png").to_return do
        image_fetches += 1
        HTTP::Client::Response.new(200, "")
      end

      Deadfinder.run_sitemap("http://sm-dupe.test/index.xml", default_test_options)

      image_fetches.should eq 0
      Deadfinder.dead_targets.should be_empty
    end

    it "still accepts <loc> entries that have no <url> wrapper" do
      # Neither a urlset nor an index by its root, but it lists pages, so it is
      # scanned rather than written off as "not a sitemap".
      WebMock.stub(:get, "http://sm-bare.test/sitemap.xml")
        .to_return(body: %(<pages><loc>http://sm-bare.test/page1</loc></pages>))
      WebMock.stub(:get, "http://sm-bare.test/page1")
        .to_return(body: %(<html><body><a href="http://sm-bare.test/dead">d</a></body></html>))
      WebMock.stub(:get, "http://sm-bare.test/dead").to_return(status: 404)

      Deadfinder.run_sitemap("http://sm-bare.test/sitemap.xml", default_test_options)

      Deadfinder.output["http://sm-bare.test/page1"].should contain "http://sm-bare.test/dead"
      Deadfinder.dead_targets.should be_empty
    end
  end

  describe "#gen_output" do
    context "when output_format is json" do
      it "writes JSON formatted output" do
        tempfile = File.tempfile("deadfinder_output", ".json")
        begin
          options = default_test_options
          options.output = tempfile.path
          options.output_format = "json"

          Deadfinder.output["http://example.com"] = ["http://example.com/page1", "http://example.com/page2"]
          Deadfinder.gen_output(options)

          content = File.read(tempfile.path)
          parsed = JSON.parse(content)
          parsed["http://example.com"].as_a.map(&.as_s).should eq ["http://example.com/page1", "http://example.com/page2"]
        ensure
          tempfile.delete
        end
      end
    end

    context "when output_format is yaml" do
      it "writes YAML formatted output" do
        tempfile = File.tempfile("deadfinder_output", ".yaml")
        begin
          options = default_test_options
          options.output = tempfile.path
          options.output_format = "yaml"

          Deadfinder.output["http://example.com"] = ["http://example.com/page1", "http://example.com/page2"]
          Deadfinder.gen_output(options)

          content = File.read(tempfile.path)
          parsed = YAML.parse(content)
          parsed["http://example.com"].as_a.map(&.as_s).should eq ["http://example.com/page1", "http://example.com/page2"]
        ensure
          tempfile.delete
        end
      end
    end

    context "when output_format is yml (alias)" do
      it "writes YAML formatted output" do
        tempfile = File.tempfile("deadfinder_output", ".yml")
        begin
          options = default_test_options
          options.output = tempfile.path
          options.output_format = "yml"

          Deadfinder.output["http://example.com"] = ["http://example.com/p1"]
          Deadfinder.gen_output(options)

          content = File.read(tempfile.path)
          parsed = YAML.parse(content)
          parsed["http://example.com"].as_a.map(&.as_s).should eq ["http://example.com/p1"]
        ensure
          tempfile.delete
        end
      end
    end

    context "when output_format is csv" do
      it "writes CSV formatted output" do
        tempfile = File.tempfile("deadfinder_output", ".csv")
        begin
          options = default_test_options
          options.output = tempfile.path
          options.output_format = "csv"

          Deadfinder.output["http://example.com"] = ["http://example.com/page1", "http://example.com/page2"]
          Deadfinder.gen_output(options)

          content = File.read(tempfile.path)
          rows = CSV.parse(content)
          rows[0].should eq ["target", "url"]
          rows.should contain ["http://example.com", "http://example.com/page1"]
          rows.should contain ["http://example.com", "http://example.com/page2"]
        ensure
          tempfile.delete
        end
      end
    end

    context "when output_format is toml" do
      it "writes TOML formatted output" do
        tempfile = File.tempfile("deadfinder_output", ".toml")
        begin
          options = default_test_options
          options.output = tempfile.path
          options.output_format = "toml"

          Deadfinder.output["http://example.com"] = ["http://example.com/page1"]
          Deadfinder.gen_output(options)

          content = File.read(tempfile.path)
          content.should contain "\"http://example.com\""
          content.should contain "\"http://example.com/page1\""
        ensure
          tempfile.delete
        end
      end

      it "escapes control characters so the output stays valid single-line TOML" do
        tempfile = File.tempfile("deadfinder_toml_ctrl", ".toml")
        begin
          options = default_test_options
          options.output = tempfile.path
          options.output_format = "toml"

          # A URL with an embedded newline/tab (e.g. from malformed scanned HTML)
          # must not emit raw control chars, which would be unparseable TOML.
          Deadfinder.output["http://example.com"] = ["http://example.com/a\nb\tc"]
          Deadfinder.gen_output(options)

          content = File.read(tempfile.path)
          content.should contain "\\n"
          content.should contain "\\t"
          # No raw newline inside the value -> the array stays on a single line.
          content.lines.size.should eq 1
        ensure
          tempfile.delete
        end
      end
    end

    context "when output_format is sarif" do
      it "writes a valid SARIF 2.1.0 document with a DEAD_LINK result per broken URL" do
        tempfile = File.tempfile("deadfinder_output", ".sarif")
        begin
          options = default_test_options
          options.output = tempfile.path
          options.output_format = "sarif"

          Deadfinder.output["http://example.com"] = ["http://example.com/page1", "http://example.com/page2"]
          Deadfinder.gen_output(options)

          content = File.read(tempfile.path)
          parsed = JSON.parse(content)

          parsed["version"].as_s.should eq "2.1.0"
          parsed["$schema"].as_s.should contain "sarif-schema-2.1.0"

          run = parsed["runs"].as_a.first
          run["tool"]["driver"]["name"].as_s.should eq "deadfinder"
          run["tool"]["driver"]["version"].as_s.should eq Deadfinder::VERSION

          rules = run["tool"]["driver"]["rules"].as_a
          rules.size.should eq 1
          rules[0]["id"].as_s.should eq "DEAD_LINK"

          results = run["results"].as_a
          results.size.should eq 2
          result_uris = results.map { |r| r["locations"].as_a.first["physicalLocation"]["artifactLocation"]["uri"].as_s }
          result_uris.should contain "http://example.com/page1"
          result_uris.should contain "http://example.com/page2"
          results.each do |r|
            r["ruleId"].as_s.should eq "DEAD_LINK"
            r["level"].as_s.should eq "warning"
            r["relatedLocations"].as_a.first["physicalLocation"]["artifactLocation"]["uri"].as_s.should eq "http://example.com"
          end
        ensure
          tempfile.delete
        end
      end

      it "produces an empty results array when there are no dead links" do
        tempfile = File.tempfile("deadfinder_output", ".sarif")
        begin
          options = default_test_options
          options.output = tempfile.path
          options.output_format = "sarif"

          Deadfinder.gen_output(options)

          content = File.read(tempfile.path)
          parsed = JSON.parse(content)
          parsed["version"].as_s.should eq "2.1.0"
          run = parsed["runs"].as_a.first
          run["tool"]["driver"]["name"].as_s.should eq "deadfinder"
        ensure
          tempfile.delete
        end
      end
    end

    context "when a URL is not valid UTF-8" do
      # A Latin-1 `é`, as it arrives from a URL list or a redirect `Location`.
      {"json", "yaml", "toml", "csv", "sarif"}.each do |format|
        it "still writes a #{format} report, and writes it as valid UTF-8" do
          tempfile = File.tempfile("deadfinder_invalid_utf8", ".#{format}")
          begin
            options = default_test_options
            options.output = tempfile.path
            options.output_format = format
            options.coverage = true

            Deadfinder.output["http://example.com/caf\xE9"] = ["http://example.com/caf\xE9/dead"]
            Deadfinder.coverage_data["http://example.com/caf\xE9"] = Deadfinder::TargetCoverage.new(total: 1, dead: 1)
            Deadfinder.dead_targets["http://example.com/gone\xE9"] = "404"
            Deadfinder.gen_output(options)

            content = File.read(tempfile.path)
            content.valid_encoding?.should be_true
            content.should contain "http://example.com/caf\uFFFD/dead"
            content.should contain "http://example.com/gone\uFFFD"
          ensure
            tempfile.delete
          end
        end
      end
    end

    context "when output is empty" do
      it "does nothing if output file is not specified" do
        options = default_test_options
        options.output = ""
        options.output_format = "json"
        # Should not raise
        Deadfinder.gen_output(options)
      end
    end

    context "when the output path is not writable" do
      it "logs an error instead of crashing" do
        options = default_test_options
        # Parent directory does not exist -> File.write raises IO::Error.
        options.output = File.join(Dir.tempdir, "deadfinder_no_such_dir_#{Time.utc.to_unix_ns}", "out.json")
        options.output_format = "json"

        Deadfinder.output["http://example.com"] = ["http://example.com/dead"]
        # Should not raise; the bad path is reported and the run finishes.
        Deadfinder.gen_output(options)
        File.exists?(options.output).should be_false
      end

      it "records the failed write as an I/O failure" do
        options = default_test_options
        options.output = File.join(Dir.tempdir, "deadfinder_no_such_dir_#{Time.utc.to_unix_ns}", "out.json")

        Deadfinder.gen_output(options)

        Deadfinder.io_failed?.should be_true
      end
    end
  end

  describe "coverage functionality" do
    describe "#calculate_coverage" do
      it "calculates coverage correctly for single target" do
        target = "http://example.com"
        Deadfinder.coverage_data[target] = Deadfinder::TargetCoverage.new(total: 10, dead: 3)

        coverage = Deadfinder.calculate_coverage

        coverage.targets[target].total_tested.should eq 10
        coverage.targets[target].dead_links.should eq 3
        coverage.targets[target].coverage_percentage.should eq 30.0
        coverage.summary.total_tested.should eq 10
        coverage.summary.total_dead.should eq 3
        coverage.summary.overall_coverage_percentage.should eq 30.0
      end

      it "calculates coverage correctly for multiple targets" do
        Deadfinder.coverage_data["http://example1.com"] = Deadfinder::TargetCoverage.new(total: 10, dead: 2)
        Deadfinder.coverage_data["http://example2.com"] = Deadfinder::TargetCoverage.new(total: 20, dead: 5)

        coverage = Deadfinder.calculate_coverage

        coverage.targets["http://example1.com"].coverage_percentage.should eq 20.0
        coverage.targets["http://example2.com"].coverage_percentage.should eq 25.0
        coverage.summary.total_tested.should eq 30
        coverage.summary.total_dead.should eq 7
        coverage.summary.overall_coverage_percentage.should eq 23.33
      end

      it "handles zero total URLs correctly" do
        target = "http://example.com"
        Deadfinder.coverage_data[target] = Deadfinder::TargetCoverage.new(total: 0, dead: 0)

        coverage = Deadfinder.calculate_coverage

        coverage.targets[target].coverage_percentage.should eq 0.0
        coverage.summary.overall_coverage_percentage.should eq 0.0
      end

      it "aggregates status counts across targets" do
        Deadfinder.coverage_data["http://a.com"] = Deadfinder::TargetCoverage.new(
          total: 5, dead: 2,
          status_counts: {"200" => 3, "404" => 2}
        )
        Deadfinder.coverage_data["http://b.com"] = Deadfinder::TargetCoverage.new(
          total: 3, dead: 1,
          status_counts: {"200" => 2, "500" => 1}
        )

        coverage = Deadfinder.calculate_coverage

        coverage.summary.overall_status_counts["200"].should eq 5
        coverage.summary.overall_status_counts["404"].should eq 2
        coverage.summary.overall_status_counts["500"].should eq 1
      end
    end

    describe "#gen_output with coverage" do
      it "includes coverage data in JSON when coverage flag is enabled" do
        tempfile = File.tempfile("deadfinder_coverage", ".json")
        begin
          options = default_test_options
          options.output = tempfile.path
          options.output_format = "json"
          options.coverage = true

          Deadfinder.output["http://example.com"] = ["http://example.com/dead1"]
          Deadfinder.coverage_data["http://example.com"] = Deadfinder::TargetCoverage.new(total: 5, dead: 1)

          Deadfinder.gen_output(options)
          content = File.read(tempfile.path)
          parsed = JSON.parse(content)

          parsed["dead_links"].should_not be_nil
          parsed["coverage"].should_not be_nil
          parsed["dead_links"]["http://example.com"].as_a.map(&.as_s).should eq ["http://example.com/dead1"]
          parsed["coverage"]["targets"]["http://example.com"]["total_tested"].as_i.should eq 5
          parsed["coverage"]["targets"]["http://example.com"]["dead_links"].as_i.should eq 1
          parsed["coverage"]["targets"]["http://example.com"]["coverage_percentage"].as_f.should eq 20.0
        ensure
          tempfile.delete
        end
      end

      it "does not include coverage data when coverage flag is disabled" do
        tempfile = File.tempfile("deadfinder_coverage", ".json")
        begin
          options = default_test_options
          options.output = tempfile.path
          options.output_format = "json"
          options.coverage = false

          Deadfinder.output["http://example.com"] = ["http://example.com/dead1"]
          Deadfinder.coverage_data["http://example.com"] = Deadfinder::TargetCoverage.new(total: 5, dead: 1)

          Deadfinder.gen_output(options)
          content = File.read(tempfile.path)
          parsed = JSON.parse(content)

          parsed["dead_links"]?.should be_nil
          parsed["coverage"]?.should be_nil
          parsed["http://example.com"].as_a.map(&.as_s).should eq ["http://example.com/dead1"]
        ensure
          tempfile.delete
        end
      end

      it "includes coverage data in YAML" do
        tempfile = File.tempfile("deadfinder_coverage", ".yaml")
        begin
          options = default_test_options
          options.output = tempfile.path
          options.output_format = "yaml"
          options.coverage = true

          Deadfinder.output["http://example.com"] = ["http://example.com/dead1"]
          Deadfinder.coverage_data["http://example.com"] = Deadfinder::TargetCoverage.new(total: 10, dead: 2)

          Deadfinder.gen_output(options)
          content = File.read(tempfile.path)
          parsed = YAML.parse(content)

          parsed["dead_links"].should_not be_nil
          parsed["coverage"].should_not be_nil
          parsed["coverage"]["targets"]["http://example.com"]["total_tested"].as_i.should eq 10
        ensure
          tempfile.delete
        end
      end

      it "generates CSV with coverage information" do
        tempfile = File.tempfile("deadfinder_coverage", ".csv")
        begin
          options = default_test_options
          options.output = tempfile.path
          options.output_format = "csv"
          options.coverage = true

          Deadfinder.output["http://example.com"] = ["http://example.com/dead1"]
          Deadfinder.coverage_data["http://example.com"] = Deadfinder::TargetCoverage.new(total: 5, dead: 1)

          Deadfinder.gen_output(options)
          content = File.read(tempfile.path)
          rows = CSV.parse(content)

          rows.should contain ["target", "url"]
          rows.should contain ["http://example.com", "http://example.com/dead1"]
          rows.any? { |r| r.includes?("Coverage Report") }.should be_true
          # The correctly-named percentage column is appended after the
          # deprecated `coverage_percentage` one, so positional readers of the
          # original four columns keep working.
          rows.should contain ["target", "total_tested", "dead_links", "coverage_percentage", "dead_link_percentage"]
          rows.should contain ["http://example.com", "5", "1", "20.0%", "20.0%"]
          rows.any? { |r| r.includes?("Overall Summary") }.should be_true
        ensure
          tempfile.delete
        end
      end

      it "generates CSV without coverage when flag is disabled" do
        tempfile = File.tempfile("deadfinder_coverage", ".csv")
        begin
          options = default_test_options
          options.output = tempfile.path
          options.output_format = "csv"
          options.coverage = false

          Deadfinder.output["http://example.com"] = ["http://example.com/dead1"]

          Deadfinder.gen_output(options)
          content = File.read(tempfile.path)
          rows = CSV.parse(content)

          rows.should contain ["target", "url"]
          rows.should contain ["http://example.com", "http://example.com/dead1"]
          rows.any? { |r| r.includes?("Coverage Report") }.should be_false
        ensure
          tempfile.delete
        end
      end

      it "includes coverage data in TOML" do
        tempfile = File.tempfile("deadfinder_coverage", ".toml")
        begin
          options = default_test_options
          options.output = tempfile.path
          options.output_format = "toml"
          options.coverage = true

          Deadfinder.output["http://example.com"] = ["http://example.com/dead1"]
          Deadfinder.coverage_data["http://example.com"] = Deadfinder::TargetCoverage.new(total: 4, dead: 1)

          Deadfinder.gen_output(options)
          content = File.read(tempfile.path)

          content.should contain "[dead_links]"
          content.should contain "[coverage.summary]"
          content.should contain "total_tested = 4"
          content.should contain "total_dead = 1"
        ensure
          tempfile.delete
        end
      end
    end

    describe "end-to-end coverage with mock" do
      it "tracks coverage through run_url" do
        target = "http://mock-cov.test"
        html = <<-HTML
          <html><body>
            <a href="http://mock-cov.test/ok">OK</a>
            <a href="http://mock-cov.test/dead">Dead</a>
          </body></html>
        HTML

        WebMock.stub(:get, target).to_return(body: html)
        WebMock.stub(:get, "http://mock-cov.test/ok").to_return(status: 200)
        WebMock.stub(:get, "http://mock-cov.test/dead").to_return(status: 404)

        tempfile = File.tempfile("deadfinder_e2e_cov", ".json")
        begin
          options = default_test_options
          options.coverage = true
          options.output = tempfile.path
          options.output_format = "json"

          Deadfinder.run_url(target, options)

          content = File.read(tempfile.path)
          parsed = JSON.parse(content)

          parsed["coverage"]["targets"][target]["total_tested"].as_i.should eq 2
          parsed["coverage"]["targets"][target]["dead_links"].as_i.should eq 1
          parsed["coverage"]["summary"]["total_tested"].as_i.should eq 2
          parsed["coverage"]["summary"]["total_dead"].as_i.should eq 1
        ensure
          tempfile.delete
        end
      end
    end
  end
end
