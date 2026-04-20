require "./spec_helper"

describe Deadfinder do
  before_each do
    WebMock.reset
    reset_deadfinder_state
  end

  describe "#version" do
    it "returns the version number" do
      Deadfinder::VERSION.should_not be_nil
      Deadfinder::VERSION.should eq "1.10.0"
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
          rows.should contain ["target", "total_tested", "dead_links", "coverage_percentage"]
          rows.should contain ["http://example.com", "5", "1", "20.0%"]
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
