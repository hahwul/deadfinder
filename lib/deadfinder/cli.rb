# frozen_string_literal: true

require 'thor'
require 'deadfinder'

module DeadFinder
  # CLI class for handling command-line interactions
  class CLI < Thor
    class_option :include30x, aliases: :r, default: false, type: :boolean, desc: 'Include 30x redirections'
    class_option :concurrency, aliases: :c, default: 50, type: :numeric, desc: 'Number of concurrency'
    class_option :timeout, aliases: :t, default: 10, type: :numeric, desc: 'Timeout in seconds'
    class_option :output, aliases: :o, default: '', type: :string, desc: 'File to write result (e.g., json, yaml, csv)'
    class_option :output_format, aliases: :f, default: 'json', type: :string, desc: 'Output format'
    class_option :headers, aliases: :H, default: [], type: :array,
                           desc: 'Custom HTTP headers to send with initial request'
    class_option :worker_headers, default: [], type: :array, desc: 'Custom HTTP headers to send with worker requests'
    class_option :user_agent, default: 'Mozilla/5.0 (compatible; DeadFinder/1.6.1;)', type: :string,
                              desc: 'User-Agent string to use for requests'
    class_option :proxy, aliases: :p, default: '', type: :string, desc: 'Proxy server to use for requests'
    class_option :proxy_auth, default: '', type: :string, desc: 'Proxy server authentication credentials'
    class_option :silent, aliases: :s, default: false, type: :boolean, desc: 'Silent mode'
    class_option :verbose, aliases: :v, default: false, type: :boolean, desc: 'Verbose mode'

    desc 'pipe', 'Scan the URLs from STDIN. (e.g., cat urls.txt | deadfinder pipe)'
    def pipe
      DeadFinder.run_pipe options
    end

    desc 'file <FILE>', 'Scan the URLs from File. (e.g., deadfinder file urls.txt)'
    def file(filename)
      DeadFinder.run_file filename, options
    end

    desc 'url <URL>', 'Scan the Single URL.'
    def url(url)
      DeadFinder.run_url url, options
    end

    desc 'sitemap <SITEMAP-URL>', 'Scan the URLs from sitemap.'
    def sitemap(sitemap)
      DeadFinder.run_sitemap sitemap, options
    end

    desc 'version', 'Show version.'
    def version
      Logger.info "deadfinder #{DeadFinder::VERSION}"
    end
  end
end
