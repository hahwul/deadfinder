# frozen_string_literal: true

require 'spec_helper'
require 'deadfinder/cli'
require 'tempfile' # Required for Tempfile

RSpec.describe DeadFinder::CLI do
  let(:cli) { described_class.new }

  before do
    # Allow all original methods by default, we will set expectations on run_with_target
    allow(DeadFinder).to receive(:run_pipe).and_call_original
    allow(DeadFinder).to receive(:run_file).and_call_original
    allow(DeadFinder).to receive(:run_url).and_call_original
    allow(DeadFinder).to receive(:run_sitemap).and_call_original
    allow(DeadFinder).to receive(:run_with_target) # This will be our main spy
    allow(DeadFinder).to receive(:gen_output) # Stub this to prevent file writing during tests
    allow(DeadFinder::Logger).to receive(:info)
    allow(DeadFinder::Logger).to receive(:error)
    allow(DeadFinder::Logger).to receive(:target)
    allow(DeadFinder::Logger).to receive(:apply_options)

    # Mock Runner instance and its run method
    # allow_any_instance_of(DeadFinder::Runner).to receive(:run)
  end

  describe '.exit_on_failure?' do
    it 'returns true' do
      expect(described_class.exit_on_failure?).to be true
    end
  end

  describe '#pipe' do
    it 'runs the pipe command' do
      cli.invoke(:pipe)
      expect(DeadFinder).to have_received(:run_pipe)
    end

    context 'with --limit option' do
      it 'respects the URL limit' do
        urls = %w[url1 url2 url3 url4 url5]
        allow($stdin).to receive(:gets).and_return(*urls, nil)
        # Invoke with options passed directly, as invoke doesn't parse them from ARGV for options hash
        cli.invoke(:pipe, [], { limit: 2 })
        expect(DeadFinder).to have_received(:run_with_target).exactly(2).times
      end
    end
  end

  describe '#file' do
    let(:temp_file) do
      Tempfile.new('urls.txt').tap do |f|
        5.times { |i| f.puts "http://example.com/url#{i + 1}" }
        f.close
      end
    end
    let(:temp_file_path) { temp_file.path }

    after do
      File.unlink(temp_file_path) if File.exist?(temp_file_path)
    end

    it 'runs the file command with a filename' do
      cli.invoke(:file, [temp_file_path])
      expect(DeadFinder).to have_received(:run_file).with(temp_file_path, anything)
      expect(DeadFinder).to have_received(:run_with_target).exactly(5).times
    end

    context 'with --limit option' do
      it 'respects the URL limit when limit is set' do
        # Thor passes options after subcommand args.
        # The options hash for invoke should be the last argument.
        # For options like --limit N, it's parsed by Thor into options['limit']
        cli.invoke(:file, [temp_file_path], { limit: 3 })
        expect(DeadFinder).to have_received(:run_with_target).exactly(3).times
      end

      it 'processes all URLs when limit is 0' do
        cli.invoke(:file, [temp_file_path], { limit: 0 })
        expect(DeadFinder).to have_received(:run_with_target).exactly(5).times
      end

      it 'processes all URLs when limit is not specified' do
        # Simulate no --limit by not passing it in options
        cli.invoke(:file, [temp_file_path], {}) # Pass empty options or specific options without limit
        expect(DeadFinder).to have_received(:run_with_target).exactly(5).times
      end
    end
  end

  describe '#url' do
    it 'runs the url command with a URL' do
      cli.invoke(:url, ['http://example.com'])
      expect(DeadFinder).to have_received(:run_url).with('http://example.com', anything)
    end
  end

  describe '#sitemap' do
    let(:sitemap_url) { 'http://example.com/sitemap.xml' }
    let(:mock_sitemap_parser) { instance_double(SitemapParser) }
    let(:sitemap_urls) { Array.new(5) { |i| "http://example.com/sitemap_url#{i + 1}" } }

    before do
      allow(SitemapParser).to receive(:new).with(sitemap_url, recurse: true).and_return(mock_sitemap_parser)
      allow(mock_sitemap_parser).to receive(:to_a).and_return(sitemap_urls)
    end

    it 'runs the sitemap command with a sitemap URL' do
      cli.invoke(:sitemap, [sitemap_url])
      expect(DeadFinder).to have_received(:run_sitemap).with(sitemap_url, anything)
      expect(DeadFinder).to have_received(:run_with_target).exactly(5).times
    end

    context 'with --limit option' do
      it 'respects the URL limit' do
        cli.invoke(:sitemap, [sitemap_url], { limit: 4 })
        expect(DeadFinder).to have_received(:run_with_target).exactly(4).times
      end

      it 'processes all URLs when limit is 0' do
        cli.invoke(:sitemap, [sitemap_url], { limit: 0 })
        expect(DeadFinder).to have_received(:run_with_target).exactly(5).times
      end

      it 'processes all URLs when limit is not specified' do
        cli.invoke(:sitemap, [sitemap_url], {})
        expect(DeadFinder).to have_received(:run_with_target).exactly(5).times
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
