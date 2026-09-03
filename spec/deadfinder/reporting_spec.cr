require "../spec_helper"

# Covers the CI-facing half of the reporting surface: the `--fail-on-dead`
# exit code, `-o -` streaming to STDOUT, the `dead_targets` key, and the
# correctly-named dead-link percentage fields.
describe "reporting" do
  before_each do
    WebMock.reset
    reset_deadfinder_state
  end

  describe "--fail-on-dead" do
    it "is off by default so a scan still exits 0" do
      Deadfinder::Options.new.fail_on_dead.should be_false
    end

    it "uses an exit code distinct from the usage/IO error code 1" do
      Deadfinder::EXIT_DEAD_FOUND.should eq 2
    end

    it "reports no findings on a clean run" do
      Deadfinder.dead_findings?.should be_false
    end

    it "ignores targets whose dead-link list is empty" do
      Deadfinder.output["http://example.com"] = [] of String
      Deadfinder.dead_findings?.should be_false
    end

    it "reports findings when a dead link was recorded" do
      Deadfinder.output["http://example.com"] = ["http://example.com/dead"]
      Deadfinder.dead_findings?.should be_true
    end

    it "reports findings when only the target itself was dead" do
      Deadfinder.dead_targets["http://example.com"] = "404"
      Deadfinder.dead_findings?.should be_true
    end

    it "does not exit when the flag is given but nothing is dead" do
      target = "http://mock-fod.test"
      html = <<-HTML
        <html><body><a href="http://mock-fod.test/ok">OK</a></body></html>
      HTML
      WebMock.stub(:get, target).to_return(body: html)
      WebMock.stub(:get, "#{target}/ok").to_return(status: 200)

      # Reaching the next line at all is the assertion: `exit_on_findings`
      # would terminate the spec process if it fired.
      Deadfinder::CLI.run(["url", target, "-s", "--fail-on-dead"])
      Deadfinder.dead_findings?.should be_false
    end
  end

  describe ".record_dead_target" do
    it "records a 4xx target under its numeric status" do
      options = default_test_options
      Deadfinder.record_dead_target("http://example.com", 404, options)
      Deadfinder.dead_targets["http://example.com"].should eq "404"
    end

    it "records a 5xx target" do
      options = default_test_options
      Deadfinder.record_dead_target("http://example.com", 503, options)
      Deadfinder.dead_targets["http://example.com"].should eq "503"
    end

    it "records an unreachable target as \"error\"" do
      options = default_test_options
      Deadfinder.record_dead_target("http://example.com", Deadfinder::Runner::ERROR_STATUS, options)
      Deadfinder.dead_targets["http://example.com"].should eq "error"
    end

    it "ignores a healthy target" do
      options = default_test_options
      Deadfinder.record_dead_target("http://example.com", 200, options)
      Deadfinder.dead_targets.should be_empty
    end

    it "ignores a 30x target unless --include30x is set" do
      options = default_test_options
      Deadfinder.record_dead_target("http://example.com", 301, options)
      Deadfinder.dead_targets.should be_empty

      options.include30x = true
      Deadfinder.record_dead_target("http://example.com", 301, options)
      Deadfinder.dead_targets["http://example.com"].should eq "301"
    end
  end

  describe "dead targets through a real run" do
    it "records a target that returns 404" do
      target = "http://mock-dead-target.test"
      WebMock.stub(:get, target).to_return(status: 404, body: "")

      Deadfinder.run_url(target, default_test_options)

      Deadfinder.dead_targets[target].should eq "404"
    end

    it "records a target that cannot be reached at all" do
      # No stub registered, so the HTTP client raises the way a refused
      # connection does.
      target = "http://mock-unreachable.test"

      Deadfinder.run_url(target, default_test_options)

      Deadfinder.dead_targets[target].should eq "error"
    end

    it "leaves dead_targets empty for a healthy target" do
      target = "http://mock-live-target.test"
      WebMock.stub(:get, target).to_return(body: "<html><body></body></html>")

      Deadfinder.run_url(target, default_test_options)

      Deadfinder.dead_targets.should be_empty
    end
  end

  describe "dead_targets in the output" do
    it "is absent from JSON when nothing is dead" do
      json = JSON.parse(report_for("json"))
      json.as_h.has_key?("dead_targets").should be_false
    end

    it "appears in JSON alongside the per-target keys" do
      Deadfinder.output["http://example.com"] = ["http://example.com/dead"]
      Deadfinder.dead_targets["http://gone.test"] = "404"

      json = JSON.parse(report_for("json"))
      json["dead_targets"]["http://gone.test"].as_s.should eq "404"
      json["http://example.com"].as_a.map(&.as_s).should eq ["http://example.com/dead"]
    end

    it "appears in JSON next to dead_links when coverage is on" do
      Deadfinder.dead_targets["http://gone.test"] = "error"

      json = JSON.parse(report_for("json", coverage: true))
      json["dead_targets"]["http://gone.test"].as_s.should eq "error"
      json["dead_links"].should_not be_nil
      json["coverage"].should_not be_nil
    end

    it "appears in YAML" do
      Deadfinder.dead_targets["http://gone.test"] = "500"

      yaml = YAML.parse(report_for("yaml"))
      yaml["dead_targets"]["http://gone.test"].as_s.should eq "500"
    end

    it "is absent from YAML when nothing is dead" do
      YAML.parse(report_for("yaml")).as_h.has_key?(YAML::Any.new("dead_targets")).should be_false
    end

    it "appears in TOML as its own table" do
      Deadfinder.output["http://example.com"] = ["http://example.com/dead"]
      Deadfinder.dead_targets["http://gone.test"] = "404"

      toml = report_for("toml")
      toml.should contain "[dead_targets]"
      toml.should contain "\"http://gone.test\" = \"404\""
      # The table header must come after the bare top-level pairs, or the
      # dead-link entries would be parsed as part of the table.
      toml.index("\"http://example.com\"").not_nil!.should be < toml.index("[dead_targets]").not_nil!
    end

    it "is absent from TOML when nothing is dead" do
      report_for("toml").should_not contain "[dead_targets]"
    end

    it "appears in CSV as its own section" do
      Deadfinder.dead_targets["http://gone.test"] = "error"

      rows = CSV.parse(report_for("csv"))
      rows.any? { |r| r.includes?("Dead Targets") }.should be_true
      rows.should contain ["target", "status"]
      rows.should contain ["http://gone.test", "error"]
    end

    it "is absent from CSV when nothing is dead" do
      CSV.parse(report_for("csv")).any? { |r| r.includes?("Dead Targets") }.should be_false
    end

    it "appears in SARIF under the DEAD_TARGET rule" do
      Deadfinder.dead_targets["http://gone.test"] = "404"

      sarif = JSON.parse(report_for("sarif"))
      run = sarif["runs"].as_a.first
      rules = run["tool"]["driver"]["rules"].as_a.map { |r| r["id"].as_s }
      rules.should contain "DEAD_TARGET"
      results = run["results"].as_a
      results.map { |r| r["ruleId"].as_s }.should contain "DEAD_TARGET"
    end

    it "declares no DEAD_TARGET rule in SARIF when nothing is dead" do
      Deadfinder.output["http://example.com"] = ["http://example.com/dead"]

      sarif = JSON.parse(report_for("sarif"))
      rules = sarif["runs"].as_a.first["tool"]["driver"]["rules"].as_a.map { |r| r["id"].as_s }
      rules.should contain "DEAD_LINK"
      rules.should_not contain "DEAD_TARGET"
    end
  end

  describe "dead targets in coverage accounting" do
    it "counts a dead target as one tested-and-dead unit" do
      Deadfinder.dead_targets["http://gone.test"] = "404"

      coverage = Deadfinder.calculate_coverage

      coverage.targets["http://gone.test"].total_tested.should eq 1
      coverage.targets["http://gone.test"].dead_links.should eq 1
      coverage.targets["http://gone.test"].dead_link_percentage.should eq 100.0
      coverage.targets["http://gone.test"].status_counts["404"].should eq 1
      coverage.summary.total_tested.should eq 1
      coverage.summary.total_dead.should eq 1
      coverage.summary.overall_status_counts["404"].should eq 1
    end

    it "merges with the link counts of a target that is dead but still served links" do
      Deadfinder.coverage_data["http://gone.test"] = Deadfinder::TargetCoverage.new(
        total: 3, dead: 1, status_counts: {"200" => 2, "404" => 1}
      )
      Deadfinder.dead_targets["http://gone.test"] = "404"

      coverage = Deadfinder.calculate_coverage

      coverage.targets["http://gone.test"].total_tested.should eq 4
      coverage.targets["http://gone.test"].dead_links.should eq 2
      coverage.targets["http://gone.test"].status_counts["404"].should eq 2
    end

    it "emits a coverage block even when only the targets were dead" do
      Deadfinder.dead_targets["http://gone.test"] = "error"

      json = JSON.parse(report_for("json", coverage: true))
      json["coverage"]["summary"]["total_tested"].as_i.should eq 1
    end

    it "leaves the module-level coverage_data untouched" do
      Deadfinder.dead_targets["http://gone.test"] = "404"
      Deadfinder.calculate_coverage
      Deadfinder.coverage_data.should be_empty
    end
  end

  describe "dead-link percentage field names" do
    it "exposes correctly named accessors on the coverage structs" do
      Deadfinder.coverage_data["http://example.com"] = Deadfinder::TargetCoverage.new(total: 10, dead: 3)

      coverage = Deadfinder.calculate_coverage

      coverage.targets["http://example.com"].dead_link_percentage.should eq 30.0
      coverage.summary.overall_dead_link_percentage.should eq 30.0
    end

    it "emits both the new and the deprecated key in JSON" do
      Deadfinder.coverage_data["http://example.com"] = Deadfinder::TargetCoverage.new(total: 4, dead: 1)

      json = JSON.parse(report_for("json", coverage: true))
      target = json["coverage"]["targets"]["http://example.com"]
      target["dead_link_percentage"].as_f.should eq 25.0
      target["coverage_percentage"].as_f.should eq 25.0

      summary = json["coverage"]["summary"]
      summary["overall_dead_link_percentage"].as_f.should eq 25.0
      summary["overall_coverage_percentage"].as_f.should eq 25.0
    end

    it "emits both keys in YAML" do
      Deadfinder.coverage_data["http://example.com"] = Deadfinder::TargetCoverage.new(total: 4, dead: 1)

      yaml = YAML.parse(report_for("yaml", coverage: true))
      target = yaml["coverage"]["targets"]["http://example.com"]
      target["dead_link_percentage"].as_f.should eq 25.0
      target["coverage_percentage"].as_f.should eq 25.0
      yaml["coverage"]["summary"]["overall_dead_link_percentage"].as_f.should eq 25.0
    end

    it "emits both keys in TOML" do
      Deadfinder.coverage_data["http://example.com"] = Deadfinder::TargetCoverage.new(total: 4, dead: 1)

      toml = report_for("toml", coverage: true)
      toml.should contain "dead_link_percentage = 25.0"
      toml.should contain "coverage_percentage = 25.0"
      toml.should contain "overall_dead_link_percentage = 25.0"
      toml.should contain "overall_coverage_percentage = 25.0"
    end

    it "appends the new CSV columns after the existing ones" do
      Deadfinder.coverage_data["http://example.com"] = Deadfinder::TargetCoverage.new(total: 4, dead: 1)

      rows = CSV.parse(report_for("csv", coverage: true))
      rows.should contain ["target", "total_tested", "dead_links", "coverage_percentage", "dead_link_percentage"]
      rows.should contain ["http://example.com", "4", "1", "25.0%", "25.0%"]
      rows.should contain ["total_tested", "total_dead", "overall_coverage_percentage", "overall_dead_link_percentage"]
    end
  end

  describe "-o - streams the report to STDOUT" do
    it "writes the report to the report sink instead of a file named `-`" do
      Deadfinder.output["http://example.com"] = ["http://example.com/dead"]
      sink = IO::Memory.new
      Deadfinder.report_sink = sink

      options = default_test_options
      options.output = "-"
      options.output_format = "json"

      tmpdir = File.join(Dir.tempdir, "deadfinder_stdout_#{Time.utc.to_unix_ns}")
      Dir.mkdir_p(tmpdir)
      begin
        Dir.cd(tmpdir) { Deadfinder.gen_output(options) }
        # The whole point of the change: `-` is a stream, not a filename.
        File.exists?(File.join(tmpdir, "-")).should be_false
      ensure
        FileUtils.rm_rf(tmpdir)
        Deadfinder.reset_report_sink
      end

      parsed = JSON.parse(sink.to_s)
      parsed["http://example.com"].as_a.map(&.as_s).should eq ["http://example.com/dead"]
    end

    it "terminates the streamed report with a newline so `| jq` sees a full line" do
      Deadfinder.output["http://example.com"] = ["http://example.com/dead"]
      sink = IO::Memory.new
      Deadfinder.report_sink = sink

      options = default_test_options
      options.output = "-"
      options.output_format = "json"

      begin
        Deadfinder.gen_output(options)
      ensure
        Deadfinder.reset_report_sink
      end

      sink.to_s.ends_with?('\n').should be_true
    end

    it "still writes to a normal path when one is given" do
      tempfile = File.tempfile("deadfinder_normal_path", ".json")
      sink = IO::Memory.new
      Deadfinder.report_sink = sink
      begin
        Deadfinder.output["http://example.com"] = ["http://example.com/dead"]
        options = default_test_options
        options.output = tempfile.path
        options.output_format = "json"

        Deadfinder.gen_output(options)

        sink.to_s.should be_empty
        JSON.parse(File.read(tempfile.path))["http://example.com"].as_a.size.should eq 1
      ensure
        Deadfinder.reset_report_sink
        tempfile.delete
      end
    end

    it "moves log output to STDERR so it cannot interleave with the report" do
      options = Deadfinder::Options.new
      options.output = "-"

      Deadfinder::Logger.apply_options(options)

      Deadfinder::Logger.sink.should be STDERR
    end

    it "leaves log output on STDOUT for a normal output path" do
      options = Deadfinder::Options.new
      options.output = "/tmp/whatever.json"

      Deadfinder::Logger.apply_options(options)

      Deadfinder::Logger.sink.should be STDOUT
    end
  end
end

# Renders the accumulated module state through `gen_output` in `format` and
# returns the file content, so each case above asserts on real emitted bytes
# rather than on an intermediate structure.
private def report_for(format : String, coverage : Bool = false) : String
  tempfile = File.tempfile("deadfinder_reporting", ".#{format}")
  begin
    options = default_test_options
    options.output = tempfile.path
    options.output_format = format
    options.coverage = coverage
    Deadfinder.gen_output(options)
    File.read(tempfile.path)
  ensure
    tempfile.delete
  end
end
