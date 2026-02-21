# frozen_string_literal: true

require 'spec_helper'
require 'webmock/rspec'
require 'deadfinder'

RSpec.describe DeadFinder::Runner do
  let(:runner) { described_class.new }
  let(:options) { runner.default_options }

  before do
    options['silent'] = true
  end

  describe '#run' do
    let(:target) { 'http://example.com' }
    let(:html) { '<html><body><a href="http://example.com/broken">Broken Link</a><a href="http://example.com/valid">Valid Link</a></body></html>' }

    before do
      stub_request(:get, target).to_return(body: html)
      stub_request(:get, 'http://example.com/broken').to_return(status: 404)
      stub_request(:get, 'http://example.com/valid').to_return(status: 200)
    end

    it 'finds broken links' do
      runner.run(target, options)
      expect(DeadFinder.output[target]).to include('http://example.com/broken')
    end

    context 'with match option' do
      before do
        options['match'] = 'broken'
      end

      it 'only includes links that match the pattern' do
        runner.run(target, options)
        expect(DeadFinder.output[target]).to include('http://example.com/broken')
        expect(DeadFinder.output[target]).not_to include('http://example.com/valid')
      end
    end

    context 'with ignore option' do
      before do
        options['ignore'] = 'valid'
      end

      it 'excludes links that match the ignore pattern' do
        runner.run(target, options)
        expect(DeadFinder.output[target]).to include('http://example.com/broken')
        expect(DeadFinder.output[target]).not_to include('http://example.com/valid')
      end
    end

    context 'with invalid match option' do
      before do
        options['match'] = '[' # Invalid regex pattern
        allow(DeadFinder::Logger).to receive(:error)
      end

      it 'logs an error for invalid match pattern' do
        runner.run(target, options)
        expect(DeadFinder::Logger).to have_received(:error).with(/Invalid match pattern/)
      end
    end

    context 'with invalid ignore option' do
      before do
        options['ignore'] = '[' # Invalid regex pattern
        allow(DeadFinder::Logger).to receive(:error)
      end

      it 'logs an error for invalid ignore pattern' do
        runner.run(target, options)
        expect(DeadFinder::Logger).to have_received(:error).with(/Invalid match pattern/)
      end
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
    let(:html) do
      <<~HTML
        <html>
          <body>
            <a href="http://example.com/anchor">Anchor</a>
            <script src="http://example.com/script.js"></script>
            <link href="http://example.com/style.css" rel="stylesheet">
            <iframe src="http://example.com/frame"></iframe>
            <form action="http://example.com/form"></form>
            <object data="http://example.com/object"></object>
            <embed src="http://example.com/embed">
            <!-- Missing attributes -->
            <a>Anchor No Href</a>
            <script>Script No Src</script>
            <link>Link No Href</link>
            <iframe>Frame No Src</iframe>
            <form>Form No Action</form>
            <object>Object No Data</object>
            <embed>Embed No Src</embed>
          </body>
        </html>
      HTML
    end
    let(:page) { Nokogiri::HTML(html) }

    it 'extracts links from the page' do
      links = runner.send(:extract_links, page)

      expect(links[:anchor]).to include('http://example.com/anchor')
      expect(links[:script]).to include('http://example.com/script.js')
      expect(links[:link]).to include('http://example.com/style.css')
      expect(links[:iframe]).to include('http://example.com/frame')
      expect(links[:form]).to include('http://example.com/form')
      expect(links[:object]).to include('http://example.com/object')
      expect(links[:embed]).to include('http://example.com/embed')
    end

    it 'compacts nil values from missing attributes' do
      links = runner.send(:extract_links, page)

      expect(links[:anchor]).not_to include(nil)
      expect(links[:script]).not_to include(nil)
      expect(links[:link]).not_to include(nil)
      expect(links[:iframe]).not_to include(nil)
      expect(links[:form]).not_to include(nil)
      expect(links[:object]).not_to include(nil)
      expect(links[:embed]).not_to include(nil)

      # Ensure only valid links are present
      expect(links[:anchor].size).to eq(1)
      expect(links[:script].size).to eq(1)
      expect(links[:link].size).to eq(1)
      expect(links[:iframe].size).to eq(1)
      expect(links[:form].size).to eq(1)
      expect(links[:object].size).to eq(1)
      expect(links[:embed].size).to eq(1)
    end
  end
end
