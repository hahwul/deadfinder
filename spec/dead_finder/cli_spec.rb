# frozen_string_literal: true

require 'spec_helper'
require 'deadfinder/cli'

RSpec.describe DeadFinder::CLI do
  let(:cli) { described_class.new }

  before do
    allow(DeadFinder).to receive(:run_pipe)
    allow(DeadFinder).to receive(:run_file)
    allow(DeadFinder).to receive(:run_url)
    allow(DeadFinder).to receive(:run_sitemap)
    allow(DeadFinder::Logger).to receive(:info)
  end

  describe '#pipe' do
    it 'runs the pipe command' do
      cli.invoke(:pipe)
      expect(DeadFinder).to have_received(:run_pipe).with(anything)
    end
  end

  describe '#file' do
    it 'runs the file command with a filename' do
      cli.invoke(:file, ['urls.txt'])
      expect(DeadFinder).to have_received(:run_file).with('urls.txt', anything)
    end
  end

  describe '#url' do
    it 'runs the url command with a URL' do
      cli.invoke(:url, ['http://example.com'])
      expect(DeadFinder).to have_received(:run_url).with('http://example.com', anything)
    end
  end

  describe '#sitemap' do
    it 'runs the sitemap command with a sitemap URL' do
      cli.invoke(:sitemap, ['http://example.com/sitemap.xml'])
      expect(DeadFinder).to have_received(:run_sitemap).with('http://example.com/sitemap.xml', anything)
    end
  end

  describe '#version' do
    it 'displays the version' do
      cli.invoke(:version)
      expect(DeadFinder::Logger).to have_received(:info).with("deadfinder #{DeadFinder::VERSION}")
    end
  end
end
