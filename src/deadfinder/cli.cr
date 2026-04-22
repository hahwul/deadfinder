require "option_parser"

module Deadfinder
  module CLI
    def self.run(args = ARGV)
      options = Options.new

      subcommand : String? = nil
      positional_arg : String? = nil

      global_parser = OptionParser.new do |parser|
        parser.banner = "Usage: deadfinder <command> [options]"
        parser.separator ""
        parser.separator "Commands:"
        parser.separator "  pipe                        Scan the URLs from STDIN"
        parser.separator "  file <FILE>                 Scan the URLs from File"
        parser.separator "  url <URL>                   Scan the Single URL"
        parser.separator "  sitemap <SITEMAP-URL>       Scan the URLs from sitemap"
        parser.separator "  completion <SHELL>           Generate completion script (bash/zsh/fish)"
        parser.separator "  version                     Show version"
        parser.separator ""
        parser.separator "Options:"

        parser.on("-r", "--include30x", "Include 30x redirections") { options.include30x = true }
        parser.on("-c CONCURRENCY", "--concurrency=CONCURRENCY", "Number of concurrency (default: 50)") { |v| options.concurrency = v.to_i }
        parser.on("-t TIMEOUT", "--timeout=TIMEOUT", "Timeout in seconds (default: 10)") { |v| options.timeout = v.to_i }
        parser.on("-o OUTPUT", "--output=OUTPUT", "File to write result") { |v| options.output = v }
        parser.on("-f FORMAT", "--output_format=FORMAT", "Output format: json, yaml, toml, csv, sarif (default: json)") { |v| options.output_format = v }
        parser.on("-H HEADER", "--headers=HEADER", "Custom HTTP headers for initial request") { |v| options.headers << v }
        parser.on("--worker_headers=HEADER", "Custom HTTP headers for worker requests") { |v| options.worker_headers << v }
        parser.on("--user_agent=UA", "User-Agent string") { |v| options.user_agent = v }
        parser.on("-p PROXY", "--proxy=PROXY", "Proxy server") { |v| options.proxy = v }
        parser.on("--proxy_auth=CREDS", "Proxy authentication (user:pass)") { |v| options.proxy_auth = v }
        parser.on("-k", "--insecure", "Skip TLS certificate verification (not recommended)") { options.insecure = true }
        parser.on("-m PATTERN", "--match=PATTERN", "Match URL pattern") { |v| options.match = v }
        parser.on("-i PATTERN", "--ignore=PATTERN", "Ignore URL pattern") { |v| options.ignore = v }
        parser.on("-s", "--silent", "Silent mode") { options.silent = true }
        parser.on("-v", "--verbose", "Verbose mode") { options.verbose = true }
        parser.on("--debug", "Debug mode") { options.debug = true }
        parser.on("--limit=N", "Limit number of URLs to scan") { |v| options.limit = v.to_i }
        parser.on("--coverage", "Enable coverage tracking and reporting") { options.coverage = true }
        parser.on("--visualize=PATH", "Generate visualization PNG") { |v| options.visualize = v }
        parser.on("-h", "--help", "Show help") do
          puts parser
          exit
        end

        parser.unknown_args do |remaining, _|
          if remaining.size > 0
            subcommand = remaining[0]
            positional_arg = remaining[1]? if remaining.size > 1
          end
        end
      end

      global_parser.parse(args)

      # Auto-enable coverage if visualize is set
      if !options.visualize.empty?
        options.coverage = true
      end

      case subcommand
      when "pipe"
        Deadfinder.run_pipe(options)
      when "file"
        if positional_arg
          Deadfinder.run_file(positional_arg.not_nil!, options)
        else
          STDERR.puts "Error: file command requires a filename argument"
          STDERR.puts "Usage: deadfinder file <FILE> [options]"
          exit 1
        end
      when "url"
        if positional_arg
          Deadfinder.run_url(positional_arg.not_nil!, options)
        else
          STDERR.puts "Error: url command requires a URL argument"
          STDERR.puts "Usage: deadfinder url <URL> [options]"
          exit 1
        end
      when "sitemap"
        if positional_arg
          Deadfinder.run_sitemap(positional_arg.not_nil!, options)
        else
          STDERR.puts "Error: sitemap command requires a URL argument"
          STDERR.puts "Usage: deadfinder sitemap <SITEMAP-URL> [options]"
          exit 1
        end
      when "completion"
        if positional_arg
          shell = positional_arg.not_nil!
          unless ["bash", "zsh", "fish"].includes?(shell)
            Deadfinder::Logger.error "Unsupported shell: #{shell}"
            exit 1
          end
          case shell
          when "bash"
            puts Deadfinder::Completion.bash
          when "zsh"
            puts Deadfinder::Completion.zsh
          when "fish"
            puts Deadfinder::Completion.fish
          end
        else
          STDERR.puts "Error: completion command requires a shell argument (bash/zsh/fish)"
          exit 1
        end
      when "version"
        Deadfinder::Logger.info "deadfinder #{Deadfinder::VERSION}"
      else
        puts global_parser
        exit 1 if subcommand
      end
    end
  end
end
