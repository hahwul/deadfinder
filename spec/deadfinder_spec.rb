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
end
