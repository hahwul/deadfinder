# frozen_string_literal: true

require 'spec_helper'
require 'webmock/rspec'
require 'deadfinder/runner'

RSpec.describe DeadFinder::Runner do
  let(:runner) { described_class.new }
  let(:options) { runner.default_options }

  before do
    options['silent'] = true
  end

  describe '#run' do
    let(:target) { 'http://example.com' }
    let(:html) { '<html><body><a href="http://example.com/broken">Broken Link</a></body></html>' }

    before do
      stub_request(:get, target).to_return(body: html)
      stub_request(:get, 'http://example.com/broken').to_return(status: 404)
    end

    it 'finds broken links' do
      runner.run(target, options)
      expect(DeadFinder.output[target]).to include('http://example.com/broken')
    end
  end

  describe '#worker' do
    let(:jobs) { Concurrent::Channel.new(buffer: :buffered, capacity: 10) }
    let(:results) { Concurrent::Channel.new(buffer: :buffered, capacity: 10) }
    let(:target) { 'http://example.com' }
    let(:url) { 'http://example.com/broken' }

    before do
      stub_request(:get, url).to_return(status: 404)
      jobs << url
      jobs.close
    end

    it 'processes jobs and finds broken links' do
      runner.worker(1, jobs, results, target, options)
      expect(DeadFinder.output[target]).to include(url)
    end
  end

  describe '#extract_links' do
    let(:html) { '<html><body><a href="http://example.com">Link</a></body></html>' }
    let(:page) { Nokogiri::HTML(html) }

    it 'extracts links from the page' do
      links = runner.send(:extract_links, page)
      expect(links[:anchor]).to include('http://example.com')
    end
  end
end
