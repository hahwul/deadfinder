# frozen_string_literal: true

require 'thor'
require 'deadfinder'
require 'deadfinder/completion'

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
    class_option :user_agent, default: 'Mozilla/5.0 (compatible; DeadFinder/1.9.1;)', type: :string,
                              desc: 'User-Agent string to use for requests'
    class_option :proxy, aliases: :p, default: '', type: :string, desc: 'Proxy server to use for requests'
    class_option :proxy_auth, default: '', type: :string, desc: 'Proxy server authentication credentials'
    class_option :match, aliases: :m, default: '', type: :string, desc: 'Match the URL with the given pattern'
    class_option :ignore, aliases: :i, default: '', type: :string, desc: 'Ignore the URL with the given pattern'
    class_option :silent, aliases: :s, default: false, type: :boolean, desc: 'Silent mode'
    class_option :verbose, aliases: :v, default: false, type: :boolean, desc: 'Verbose mode'
    class_option :debug, default: false, type: :boolean, desc: 'Debug mode'
    class_option :limit, default: 0, type: :numeric, desc: 'Limit the number of URLs to scan'
    class_option :coverage, default: false, type: :boolean, desc: 'Enable coverage tracking and reporting'
    class_option :visualize, default: '', type: :string, desc: 'Generate a visualization of the scan results (e.g., report.png)'

    def self.exit_on_failure?
      true
    end

    desc 'pipe', 'Scan the URLs from STDIN. (e.g., cat urls.txt | deadfinder pipe)'
    def pipe
      DeadFinder.run_pipe prepare_options
    end

    desc 'file <FILE>', 'Scan the URLs from File. (e.g., deadfinder file urls.txt)'
    def file(filename)
      DeadFinder.run_file filename, prepare_options
    end

    desc 'url <URL>', 'Scan the Single URL.'
    def url(url)
      DeadFinder.run_url url, prepare_options
    end

    desc 'sitemap <SITEMAP-URL>', 'Scan the URLs from sitemap.'
    def sitemap(sitemap)
      DeadFinder.run_sitemap sitemap, prepare_options
    end

    desc 'completion <SHELL>', 'Generate completion script for shell.'
    def completion(shell)
      unless %w[bash zsh fish].include?(shell)
        DeadFinder::Logger.error "Unsupported shell: #{shell}"
        return
      end
      case shell
      when 'bash'
        puts DeadFinder::Completion.bash
      when 'zsh'
        puts DeadFinder::Completion.zsh
      when 'fish'
        puts DeadFinder::Completion.fish
      end
    end

    desc 'version', 'Show version.'
    def version
      DeadFinder::Logger.info "deadfinder #{DeadFinder::VERSION}"
    end

    private

    def prepare_options
      opts = options.dup
      opts['coverage'] = true if opts['visualize'] && !opts['visualize'].empty?
      opts
    end
  end
end
