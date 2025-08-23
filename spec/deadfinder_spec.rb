# frozen_string_literal: true

require 'tempfile'
require 'json'
require 'yaml'
require 'csv'
require_relative '../lib/deadfinder'

RSpec.describe 'DeadFinder' do
  describe '#version' do
    it 'returns the version number' do
      expect(DeadFinder::VERSION).not_to be_nil
    end
  end

  describe '#gen_output' do
    let(:tempfile) { Tempfile.new('deadfinder_output') }
    let(:options) do
      { 'output' => tempfile.path, 'output_format' => output_format }
    end
    let(:dummy_data) do
      { 'http://example.com' => ['http://example.com/page1', 'http://example.com/page2'] }
    end

    before do
      DeadFinder.output.clear
      DeadFinder.coverage_data.clear
      DeadFinder.output.merge!(dummy_data)
    end

    context "when output_format is 'json'" do
      let(:output_format) { 'json' }

      it 'writes JSON formatted output' do
        DeadFinder.gen_output(options)
        content = File.read(tempfile.path)
        parsed = JSON.parse(content)
        expect(parsed).to eq(dummy_data)
      end
    end

    context "when output_format is 'yaml'" do
      let(:output_format) { 'yaml' }

      it 'writes YAML formatted output' do
        DeadFinder.gen_output(options)
        content = File.read(tempfile.path)
        parsed = YAML.safe_load(content)
        expect(parsed).to eq(dummy_data)
      end
    end

    context "when output_format is 'yml'" do
      let(:output_format) { 'yml' }

      it 'writes YAML formatted output' do
        DeadFinder.gen_output(options)
        content = File.read(tempfile.path)
        parsed = YAML.safe_load(content)
        expect(parsed).to eq(dummy_data)
      end
    end

    context "when output_format is 'csv'" do
      let(:output_format) { 'csv' }

      it 'writes CSV formatted output' do
        DeadFinder.gen_output(options)
        content = File.read(tempfile.path)
        csv = CSV.parse(content)
        # 첫 줄은 헤더, 이후 각 행은 target, url 값임
        expect(csv[0]).to eq(%w[target url])
        rows = csv[1..]
        expected = [
          ['http://example.com', 'http://example.com/page1'],
          ['http://example.com', 'http://example.com/page2']
        ]
        expect(rows).to match_array(expected)
      end
    end

    context 'when output is empty' do
      let(:output_format) { 'json' }

      it 'does nothing if output file is not specified' do
        options['output'] = ''
        expect { DeadFinder.gen_output(options) }.not_to raise_error
      end
    end
  end

  describe 'DeadFinder::Runner#default_options' do
    it 'provides a default options hash with expected keys' do
      runner = DeadFinder::Runner.new
      defaults = runner.default_options
      DeadFinder::Logger.apply_options(defaults)
      expect(defaults).to include(
        'concurrency' => 50,
        'timeout' => 10,
        'output' => '',
        'output_format' => 'json',
        'headers' => [],
        'worker_headers' => [],
        'silent' => true,
        'verbose' => false,
        'include30x' => false
      )
    end
  end

  describe 'Coverage functionality' do
    before do
      DeadFinder.output.clear
      DeadFinder.coverage_data.clear
    end

    describe '#calculate_coverage' do
      it 'calculates coverage correctly for single target' do
        target = 'http://example.com'
        DeadFinder.coverage_data[target] = { total: 10, dead: 3 }

        coverage = DeadFinder.calculate_coverage

        expect(coverage[:targets][target][:total_tested]).to eq(10)
        expect(coverage[:targets][target][:dead_links]).to eq(3)
        expect(coverage[:targets][target][:coverage_percentage]).to eq(30.0)
        expect(coverage[:summary][:total_tested]).to eq(10)
        expect(coverage[:summary][:total_dead]).to eq(3)
        expect(coverage[:summary][:overall_coverage_percentage]).to eq(30.0)
      end

      it 'calculates coverage correctly for multiple targets' do
        DeadFinder.coverage_data['http://example1.com'] = { total: 10, dead: 2 }
        DeadFinder.coverage_data['http://example2.com'] = { total: 20, dead: 5 }

        coverage = DeadFinder.calculate_coverage

        expect(coverage[:targets]['http://example1.com'][:coverage_percentage]).to eq(20.0)
        expect(coverage[:targets]['http://example2.com'][:coverage_percentage]).to eq(25.0)
        expect(coverage[:summary][:total_tested]).to eq(30)
        expect(coverage[:summary][:total_dead]).to eq(7)
        expect(coverage[:summary][:overall_coverage_percentage]).to eq(23.33)
      end

      it 'handles zero total URLs correctly' do
        target = 'http://example.com'
        DeadFinder.coverage_data[target] = { total: 0, dead: 0 }

        coverage = DeadFinder.calculate_coverage

        expect(coverage[:targets][target][:coverage_percentage]).to eq(0.0)
        expect(coverage[:summary][:overall_coverage_percentage]).to eq(0.0)
      end
    end

    describe '#gen_output with coverage' do
      let(:tempfile) { Tempfile.new('deadfinder_coverage_output') }
      let(:options) do
        { 'output' => tempfile.path, 'output_format' => 'json', 'coverage' => true }
      end
      let(:dummy_data) do
        { 'http://example.com' => ['http://example.com/dead1'] }
      end
      let(:dummy_coverage) do
        { 'http://example.com' => { total: 5, dead: 1 } }
      end

      before do
        DeadFinder.output.clear
        DeadFinder.coverage_data.clear
        DeadFinder.output.merge!(dummy_data)
        DeadFinder.coverage_data.merge!(dummy_coverage)
      end

      it 'includes coverage data when coverage flag is enabled' do
        DeadFinder.gen_output(options)
        content = File.read(tempfile.path)
        parsed = JSON.parse(content)

        expect(parsed).to have_key('dead_links')
        expect(parsed).to have_key('coverage')
        expect(parsed['dead_links']).to eq(dummy_data)
        expect(parsed['coverage']['targets']['http://example.com']['total_tested']).to eq(5)
        expect(parsed['coverage']['targets']['http://example.com']['dead_links']).to eq(1)
        expect(parsed['coverage']['targets']['http://example.com']['coverage_percentage']).to eq(20.0)
      end

      it 'does not include coverage data when coverage flag is disabled' do
        options['coverage'] = false
        DeadFinder.gen_output(options)
        content = File.read(tempfile.path)
        parsed = JSON.parse(content)

        expect(parsed).not_to have_key('dead_links')
        expect(parsed).not_to have_key('coverage')
        expect(parsed).to eq(dummy_data)
      end

      it 'generates CSV with coverage information when coverage flag is enabled' do
        options['output_format'] = 'csv'
        DeadFinder.gen_output(options)
        content = File.read(tempfile.path)
        csv = CSV.parse(content)

        # Should have the original data plus coverage section
        expect(csv).to include(%w[target url])
        expect(csv).to include(['http://example.com', 'http://example.com/dead1'])
        expect(csv).to include(['Coverage Report'])
        expect(csv).to include(%w[target total_tested dead_links coverage_percentage])
        expect(csv).to include(['http://example.com', '5', '1', '20.0%'])
        expect(csv).to include(['Overall Summary'])
      end

      it 'generates CSV without coverage information when coverage flag is disabled' do
        options['output_format'] = 'csv'
        options['coverage'] = false
        DeadFinder.gen_output(options)
        content = File.read(tempfile.path)
        csv = CSV.parse(content)

        # Should have only the original data without coverage section
        expect(csv).to include(%w[target url])
        expect(csv).to include(['http://example.com', 'http://example.com/dead1'])
        expect(csv).not_to include(['Coverage Report'])
      end
    end
  end

  describe 'run_url' do
    let(:url) { 'https://www.hahwul.com' }
    let(:options) { { 'output' => '', 'output_format' => 'json' } }

    it 'calls run_with_target with the URL' do
      expect(DeadFinder).to receive(:run_with_target).with(url, options)
      DeadFinder.run_url(url, options)
    end
  end
end
