# frozen_string_literal: true

require 'spec_helper'
require 'deadfinder/cli'
require 'deadfinder/visualizer'

RSpec.describe DeadFinder::CLI do
  let(:cli) { described_class.new }

  before do
    allow(DeadFinder).to receive(:run_pipe)
    allow(DeadFinder).to receive(:run_file)
    allow(DeadFinder).to receive(:run_url)
    allow(DeadFinder).to receive(:run_sitemap)
    allow(DeadFinder::Logger).to receive(:info)
    allow(DeadFinder::Logger).to receive(:error)
  end

  describe '.exit_on_failure?' do
    it 'returns true' do
      expect(described_class.exit_on_failure?).to be true
    end
  end

  describe '#pipe' do
    it 'runs the pipe command' do
      cli.invoke(:pipe)
      expect(DeadFinder).to have_received(:run_pipe).with(anything)
    end

    context 'with --limit option' do
      let(:options) { { limit: 1 } }

      it 'runs the pipe command with a limit' do
        cli.invoke(:pipe, [], options)
        expect(DeadFinder).to have_received(:run_pipe).with(hash_including(options))
      end
    end
  end

  describe '#file' do
    it 'runs the file command with a filename' do
      cli.invoke(:file, ['urls.txt'])
      expect(DeadFinder).to have_received(:run_file).with('urls.txt', anything)
    end

    context 'with --limit option' do
      let(:options) { { limit: 1 } }

      it 'runs the file command with a limit' do
        cli.invoke(:file, ['urls.txt'], options)
        expect(DeadFinder).to have_received(:run_file).with('urls.txt', hash_including(options))
      end
    end
  end

  describe '#url' do
    it 'runs the url command with a URL' do
      cli.invoke(:url, ['http://example.com'])
      expect(DeadFinder).to have_received(:run_url).with('http://example.com', anything)
    end

    context 'with --visualize option' do
      let(:options) { { 'visualize' => 'report.png', 'coverage' => true } }

      before do
        allow(DeadFinder::Visualizer).to receive(:generate)
        allow(DeadFinder).to receive(:coverage_data).and_return({ 'http://example.com' => { total: 10, dead: 2 } })
        allow(DeadFinder).to receive(:calculate_coverage).and_call_original
        allow(DeadFinder).to receive(:gen_output).and_call_original
      end

      it 'calls the visualizer' do
        allow(DeadFinder).to receive(:run_with_target)
        cli.invoke(:url, ['http://example.com'], options)
        DeadFinder.gen_output(options)
        expect(DeadFinder::Visualizer).to have_received(:generate)
      end
    end
  end

  describe '#sitemap' do
    it 'runs the sitemap command with a sitemap URL' do
      cli.invoke(:sitemap, ['http://example.com/sitemap.xml'])
      expect(DeadFinder).to have_received(:run_sitemap).with('http://example.com/sitemap.xml', anything)
    end

    context 'with --limit option' do
      let(:options) { { limit: 1 } }

      it 'runs the sitemap command with a limit' do
        cli.invoke(:sitemap, ['http://example.com/sitemap.xml'], options)
        expect(DeadFinder).to have_received(:run_sitemap).with('http://example.com/sitemap.xml', hash_including(options))
      end
    end
  end

  describe '#version' do
    it 'displays the version' do
      cli.invoke(:version)
      expect(DeadFinder::Logger).to have_received(:info).with("deadfinder #{DeadFinder::VERSION}")
    end
  end

  describe '#completion' do
    it 'generates completion script for bash' do
      expect { cli.invoke(:completion, ['bash']) }.to output(/complete -F/).to_stdout
    end

    it 'generates completion script for zsh' do
      expect { cli.invoke(:completion, ['zsh']) }.to output(/#compdef/).to_stdout
    end

    it 'generates completion script for fish' do
      expect { cli.invoke(:completion, ['fish']) }.to output(/complete -c/).to_stdout
    end

    it 'shows an error for unsupported shell' do
      cli.invoke(:completion, ['unsupported_shell'])
      expect(DeadFinder::Logger).to have_received(:error).with('Unsupported shell: unsupported_shell')
    end
  end
end
