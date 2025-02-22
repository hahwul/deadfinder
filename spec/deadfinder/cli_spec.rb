# frozen_string_literal: true

require 'spec_helper'
require 'deadfinder/cli'

RSpec.describe DeadFinder::CLI do
  let(:cli) { described_class.new }

  describe '#pipe' do
    it 'runs the pipe command' do
      expect(DeadFinder).to receive(:run_pipe).with(anything)
      cli.invoke(:pipe)
    end
  end

  describe '#file' do
    it 'runs the file command with a filename' do
      expect(DeadFinder).to receive(:run_file).with('urls.txt', anything)
      cli.invoke(:file, ['urls.txt'])
    end
  end

  describe '#url' do
    it 'runs the url command with a URL' do
      expect(DeadFinder).to receive(:run_url).with('http://example.com', anything)
      cli.invoke(:url, ['http://example.com'])
    end
  end

  describe '#sitemap' do
    it 'runs the sitemap command with a sitemap URL' do
      expect(DeadFinder).to receive(:run_sitemap).with('http://example.com/sitemap.xml', anything)
      cli.invoke(:sitemap, ['http://example.com/sitemap.xml'])
    end
  end

  describe '#version' do
    it 'displays the version' do
      expect(Logger).to receive(:info).with("deadfinder #{DeadFinder::VERSION}")
      cli.invoke(:version)
    end
  end
end
