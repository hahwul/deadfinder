require "../spec_helper"
require "stumpy_png"
require "file_utils"

describe Deadfinder::Visualizer do
  describe ".generate" do
    it "returns early when total_tested is zero" do
      data = Deadfinder::CoverageResult.new(
        targets: {} of String => Deadfinder::CoverageTarget,
        summary: Deadfinder::CoverageSummary.new(
          total_tested: 0,
          total_dead: 0,
          overall_coverage_percentage: 0.0,
          overall_status_counts: {} of String => Int32
        )
      )
      output_path = File.tempname("viz_test", ".png")
      Deadfinder::Visualizer.generate(data, output_path)
      File.exists?(output_path).should be_false
    end

    it "creates a valid 500x300 PNG with 200 status codes" do
      data = Deadfinder::CoverageResult.new(
        targets: {} of String => Deadfinder::CoverageTarget,
        summary: Deadfinder::CoverageSummary.new(
          total_tested: 10,
          total_dead: 0,
          overall_coverage_percentage: 0.0,
          overall_status_counts: {"200" => 10}
        )
      )
      output_path = File.tempname("viz_test", ".png")
      begin
        Deadfinder::Visualizer.generate(data, output_path)
        File.exists?(output_path).should be_true

        canvas = StumpyPNG.read(output_path)
        canvas.width.should eq 500
        canvas.height.should eq 300

        # Check for green pixels (200 status = green)
        green = StumpyPNG::RGBA.from_rgb8(0, 255, 0)
        green_found = (110..180).any? { |y| canvas[250, y] == green }
        green_found.should be_true
      ensure
        FileUtils.rm_rf(output_path)
      end
    end

    it "draws orange bars for 3xx status codes" do
      data = Deadfinder::CoverageResult.new(
        targets: {} of String => Deadfinder::CoverageTarget,
        summary: Deadfinder::CoverageSummary.new(
          total_tested: 10,
          total_dead: 10,
          overall_coverage_percentage: 100.0,
          overall_status_counts: {"301" => 10}
        )
      )
      output_path = File.tempname("viz_test", ".png")
      begin
        Deadfinder::Visualizer.generate(data, output_path)
        canvas = StumpyPNG.read(output_path)

        orange = StumpyPNG::RGBA.from_rgb8(255, 165, 0)
        orange_found = (110..180).any? { |y| canvas[250, y] == orange }
        orange_found.should be_true
      ensure
        FileUtils.rm_rf(output_path)
      end
    end

    it "draws red bars for 4xx status codes" do
      data = Deadfinder::CoverageResult.new(
        targets: {} of String => Deadfinder::CoverageTarget,
        summary: Deadfinder::CoverageSummary.new(
          total_tested: 10,
          total_dead: 10,
          overall_coverage_percentage: 100.0,
          overall_status_counts: {"404" => 10}
        )
      )
      output_path = File.tempname("viz_test", ".png")
      begin
        Deadfinder::Visualizer.generate(data, output_path)
        canvas = StumpyPNG.read(output_path)

        red = StumpyPNG::RGBA.from_rgb8(255, 0, 0)
        red_found = (110..180).any? { |y| canvas[250, y] == red }
        red_found.should be_true
      ensure
        FileUtils.rm_rf(output_path)
      end
    end

    it "draws purple bars for 5xx status codes" do
      data = Deadfinder::CoverageResult.new(
        targets: {} of String => Deadfinder::CoverageTarget,
        summary: Deadfinder::CoverageSummary.new(
          total_tested: 10,
          total_dead: 10,
          overall_coverage_percentage: 100.0,
          overall_status_counts: {"500" => 10}
        )
      )
      output_path = File.tempname("viz_test", ".png")
      begin
        Deadfinder::Visualizer.generate(data, output_path)
        canvas = StumpyPNG.read(output_path)

        purple = StumpyPNG::RGBA.from_rgb8(128, 0, 128)
        purple_found = (110..180).any? { |y| canvas[250, y] == purple }
        purple_found.should be_true
      ensure
        FileUtils.rm_rf(output_path)
      end
    end

    it "draws gray bars for error/unknown status codes" do
      data = Deadfinder::CoverageResult.new(
        targets: {} of String => Deadfinder::CoverageTarget,
        summary: Deadfinder::CoverageSummary.new(
          total_tested: 10,
          total_dead: 10,
          overall_coverage_percentage: 100.0,
          overall_status_counts: {"error" => 10}
        )
      )
      output_path = File.tempname("viz_test", ".png")
      begin
        Deadfinder::Visualizer.generate(data, output_path)
        canvas = StumpyPNG.read(output_path)

        gray = StumpyPNG::RGBA.from_rgb8(128, 128, 128)
        gray_found = (110..180).any? { |y| canvas[250, y] == gray }
        gray_found.should be_true
      ensure
        FileUtils.rm_rf(output_path)
      end
    end

    it "creates PNG with mixed status codes" do
      data = Deadfinder::CoverageResult.new(
        targets: {} of String => Deadfinder::CoverageTarget,
        summary: Deadfinder::CoverageSummary.new(
          total_tested: 100,
          total_dead: 60,
          overall_coverage_percentage: 60.0,
          overall_status_counts: {
            "200" => 40, "301" => 20, "404" => 20, "500" => 10, "error" => 10,
          }
        )
      )
      output_path = File.tempname("viz_test", ".png")
      begin
        Deadfinder::Visualizer.generate(data, output_path)
        File.exists?(output_path).should be_true

        canvas = StumpyPNG.read(output_path)
        canvas.width.should eq 500
        canvas.height.should eq 300
      ensure
        FileUtils.rm_rf(output_path)
      end
    end

    it "draws outline with semi-transparent black" do
      data = Deadfinder::CoverageResult.new(
        targets: {} of String => Deadfinder::CoverageTarget,
        summary: Deadfinder::CoverageSummary.new(
          total_tested: 10,
          total_dead: 5,
          overall_coverage_percentage: 50.0,
          overall_status_counts: {"200" => 5, "404" => 5}
        )
      )
      output_path = File.tempname("viz_test", ".png")
      begin
        Deadfinder::Visualizer.generate(data, output_path)
        canvas = StumpyPNG.read(output_path)

        outline = StumpyPNG::RGBA.new(0_u16, 0_u16, 0_u16, 32768_u16)
        # Top line center
        canvas[250, 100].should eq outline
        # Bottom line center
        canvas[250, 190].should eq outline
        # Left line center
        canvas[10, 145].should eq outline
        # Right line center
        canvas[490, 145].should eq outline
      ensure
        FileUtils.rm_rf(output_path)
      end
    end

    it "skips zero-height bars" do
      data = Deadfinder::CoverageResult.new(
        targets: {} of String => Deadfinder::CoverageTarget,
        summary: Deadfinder::CoverageSummary.new(
          total_tested: 10_000,
          total_dead: 0,
          overall_coverage_percentage: 0.0,
          overall_status_counts: {"200" => 1}
        )
      )
      output_path = File.tempname("viz_test", ".png")
      begin
        Deadfinder::Visualizer.generate(data, output_path)
        canvas = StumpyPNG.read(output_path)

        # With 1/10000 * 70 = 0.007, height rounds to 0 so no green bars
        green = StumpyPNG::RGBA.from_rgb8(0, 255, 0)
        green_found = (110..180).any? { |y| canvas[250, y] == green }
        green_found.should be_false
      ensure
        FileUtils.rm_rf(output_path)
      end
    end

    it "handles empty status counts" do
      data = Deadfinder::CoverageResult.new(
        targets: {} of String => Deadfinder::CoverageTarget,
        summary: Deadfinder::CoverageSummary.new(
          total_tested: 10,
          total_dead: 0,
          overall_coverage_percentage: 0.0,
          overall_status_counts: {} of String => Int32
        )
      )
      output_path = File.tempname("viz_test", ".png")
      begin
        Deadfinder::Visualizer.generate(data, output_path)
        File.exists?(output_path).should be_true
        canvas = StumpyPNG.read(output_path)
        canvas.width.should eq 500
        canvas.height.should eq 300
      ensure
        FileUtils.rm_rf(output_path)
      end
    end
  end
end
