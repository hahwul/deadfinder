# frozen_string_literal: true

require 'spec_helper'
require 'deadfinder/visualizer'
require 'tempfile'
require 'chunky_png'
require 'fileutils'
require 'securerandom'

RSpec.describe DeadFinder::Visualizer do
  describe '.generate' do
    let(:output_path) { File.join(Dir.tmpdir, "test_output_#{SecureRandom.hex(8)}.png") }

    after do
      FileUtils.rm_f(output_path)
    end

    context 'when summary is nil' do
      it 'returns early without creating a file' do
        data = { summary: nil }
        described_class.generate(data, output_path)
        expect(File.exist?(output_path)).to be false
      end
    end

    context 'when total_tested is nil' do
      it 'returns early without creating a file' do
        data = { summary: { total_tested: nil } }
        described_class.generate(data, output_path)
        expect(File.exist?(output_path)).to be false
      end
    end

    context 'when total_tested is zero' do
      it 'returns early without creating a file' do
        data = { summary: { total_tested: 0 } }
        described_class.generate(data, output_path)
        expect(File.exist?(output_path)).to be false
      end
    end

    context 'with 200 status code' do
      let(:data) do
        {
          summary: {
            total_tested: 10,
            overall_status_counts: { '200' => 10 }
          }
        }
      end

      it 'creates a valid PNG file' do
        described_class.generate(data, output_path)
        expect(File.exist?(output_path)).to be true
        png = ChunkyPNG::Image.from_file(output_path)
        expect(png.width).to eq(500)
        expect(png.height).to eq(300)
      end

      it 'draws green bars for status 200' do
        described_class.generate(data, output_path)
        png = ChunkyPNG::Image.from_file(output_path)
        # Sample specific pixel in the bar area (center of bar region)
        bar_center_x = 250
        green_color = ChunkyPNG::Color.rgb(0, 255, 0)
        green_found = (110..180).any? { |y| png[bar_center_x, y] == green_color }
        expect(green_found).to be true
      end
    end

    context 'with 3xx status codes' do
      let(:data) do
        {
          summary: {
            total_tested: 10,
            overall_status_counts: { '301' => 10 }
          }
        }
      end

      it 'draws orange bars for 3xx status codes' do
        described_class.generate(data, output_path)
        png = ChunkyPNG::Image.from_file(output_path)
        bar_center_x = 250
        orange_color = ChunkyPNG::Color.rgb(255, 165, 0)
        orange_found = (110..180).any? { |y| png[bar_center_x, y] == orange_color }
        expect(orange_found).to be true
      end
    end

    context 'with 4xx status codes' do
      let(:data) do
        {
          summary: {
            total_tested: 10,
            overall_status_counts: { '404' => 10 }
          }
        }
      end

      it 'draws red bars for 4xx status codes' do
        described_class.generate(data, output_path)
        png = ChunkyPNG::Image.from_file(output_path)
        bar_center_x = 250
        red_color = ChunkyPNG::Color.rgb(255, 0, 0)
        red_found = (110..180).any? { |y| png[bar_center_x, y] == red_color }
        expect(red_found).to be true
      end
    end

    context 'with 5xx status codes' do
      let(:data) do
        {
          summary: {
            total_tested: 10,
            overall_status_counts: { '500' => 10 }
          }
        }
      end

      it 'draws purple bars for 5xx status codes' do
        described_class.generate(data, output_path)
        png = ChunkyPNG::Image.from_file(output_path)
        bar_center_x = 250
        purple_color = ChunkyPNG::Color.rgb(128, 0, 128)
        purple_found = (110..180).any? { |y| png[bar_center_x, y] == purple_color }
        expect(purple_found).to be true
      end
    end

    context 'with unknown status codes' do
      let(:data) do
        {
          summary: {
            total_tested: 10,
            overall_status_counts: { 'error' => 10 }
          }
        }
      end

      it 'draws gray bars for unknown status codes' do
        described_class.generate(data, output_path)
        png = ChunkyPNG::Image.from_file(output_path)
        bar_center_x = 250
        gray_color = ChunkyPNG::Color.rgb(128, 128, 128)
        gray_found = (110..180).any? { |y| png[bar_center_x, y] == gray_color }
        expect(gray_found).to be true
      end
    end

    context 'with mixed status codes' do
      let(:data) do
        {
          summary: {
            total_tested: 100,
            overall_status_counts: {
              '200' => 40,
              '301' => 20,
              '404' => 20,
              '500' => 10,
              'error' => 10
            }
          }
        }
      end

      it 'creates a valid PNG file with multiple colored bars' do
        described_class.generate(data, output_path)
        expect(File.exist?(output_path)).to be true
        png = ChunkyPNG::Image.from_file(output_path)
        expect(png.width).to eq(500)
        expect(png.height).to eq(300)
      end
    end

    context 'with empty status counts' do
      let(:data) do
        {
          summary: {
            total_tested: 10,
            overall_status_counts: {}
          }
        }
      end

      it 'creates a valid PNG file with only outline' do
        described_class.generate(data, output_path)
        expect(File.exist?(output_path)).to be true
        png = ChunkyPNG::Image.from_file(output_path)
        expect(png.width).to eq(500)
        expect(png.height).to eq(300)
      end
    end

    context 'with nil overall_status_counts' do
      let(:data) do
        {
          summary: {
            total_tested: 10,
            overall_status_counts: nil
          }
        }
      end

      it 'creates a valid PNG file with only outline' do
        described_class.generate(data, output_path)
        expect(File.exist?(output_path)).to be true
        png = ChunkyPNG::Image.from_file(output_path)
        expect(png.width).to eq(500)
        expect(png.height).to eq(300)
      end
    end

    context 'with very small count resulting in zero height bar' do
      let(:data) do
        {
          summary: {
            total_tested: 10_000,
            overall_status_counts: { '200' => 1 }
          }
        }
      end

      it 'skips drawing bars with zero height' do
        described_class.generate(data, output_path)
        expect(File.exist?(output_path)).to be true
        png = ChunkyPNG::Image.from_file(output_path)
        bar_center_x = 250
        green_color = ChunkyPNG::Color.rgb(0, 255, 0)
        # With 1/10000 * 70 = 0.007, height should be 0, so no green bars
        green_found = (110..180).any? { |y| png[bar_center_x, y] == green_color }
        expect(green_found).to be false
      end
    end

    context 'with mixed zero and non-zero height bars' do
      let(:data) do
        {
          summary: {
            total_tested: 10_000,
            overall_status_counts: {
              '200' => 9_999,
              '404' => 1
            }
          }
        }
      end

      it 'draws the large bar and skips the zero-height bar' do
        described_class.generate(data, output_path)
        expect(File.exist?(output_path)).to be true
        png = ChunkyPNG::Image.from_file(output_path)
        bar_center_x = 250

        green_color = ChunkyPNG::Color.rgb(0, 255, 0)
        red_color = ChunkyPNG::Color.rgb(255, 0, 0)

        # Green bar should be present (large count)
        green_found = (110..180).any? { |y| png[bar_center_x, y] == green_color }
        expect(green_found).to be true

        # Red bar should be absent (zero height)
        red_found = (110..180).any? { |y| png[bar_center_x, y] == red_color }
        expect(red_found).to be false
      end
    end

    context 'with rounded corners and outline' do
      let(:data) do
        {
          summary: {
            total_tested: 10,
            overall_status_counts: { '200' => 5 }
          }
        }
      end

      it 'draws outline with semi-transparent black' do
        described_class.generate(data, output_path)
        png = ChunkyPNG::Image.from_file(output_path)
        outline_color = ChunkyPNG::Color.rgba(0, 0, 0, 128)
        expect(png[250, 100]).to eq(outline_color)
        expect(png[250, 190]).to eq(outline_color)
        expect(png[10, 145]).to eq(outline_color)
        expect(png[490, 145]).to eq(outline_color)
      end
    end
  end
end
