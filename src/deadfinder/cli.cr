require "option_parser"

module Deadfinder
  module CLI
    def self.run(args = ARGV)
      options = Options.new

      subcommand : String? = nil
      positional_arg : String? = nil
      extra_args = [] of String

      global_parser = OptionParser.new do |parser|
        parser.banner = "Usage: deadfinder <command> [options]"
        parser.separator ""
        parser.separator "Commands:"
        parser.separator "  pipe                        Scan the URLs from STDIN"
        parser.separator "  file <FILE>                 Scan the URLs from File (`-` for STDIN)"
        parser.separator "  url <URL>                   Scan the Single URL"
        parser.separator "  sitemap <SITEMAP-URL>       Scan the URLs from sitemap"
        parser.separator "  completion <SHELL>          Generate completion script (bash/zsh/fish)"
        parser.separator "  version                     Show version"
        parser.separator ""
        parser.separator "Options:"

        parser.on("-r", "--include30x", "Include 30x redirections") { options.include30x = true }
        parser.on("-c CONCURRENCY", "--concurrency=CONCURRENCY", "Number of concurrency (default: 50)") { |v| options.concurrency = v.to_i }
        parser.on("--target-concurrency=N", "Number of targets scanned in parallel; total in-flight requests stay capped at -c (default: 10)") { |v| options.target_concurrency = v.to_i }
        parser.on("-t TIMEOUT", "--timeout=TIMEOUT", "Timeout in seconds (default: 10)") { |v| options.timeout = v.to_i }
        parser.on("--method=METHOD", "Link check method: auto, head, get (default: auto). auto sends HEAD first and re-checks with GET on any 4xx/5xx (405/501 included), so no link is reported dead on a HEAD status alone. A HEAD that never reached the host is not re-checked") { |v| options.http_method = v.strip.downcase }
        parser.on("--retry=N", "Retry a transient failure N times: connection error, timeout, 429 or 5xx. A 404 is never retried (default: 2)") { |v| options.retries = v.to_i }
        parser.on("--delay=MS", "Minimum milliseconds between two requests to the same host; other hosts are unaffected (default: 0)") { |v| options.delay = v.to_i }
        parser.on("--accept-status=LIST", "Treat these statuses as alive, e.g. '200,204,403,999' or '400-499'. Wins over --dead-status and over the built-in >= 400 rule") { |v| options.accept_status = v }
        parser.on("--dead-status=LIST", "Treat these statuses as dead, e.g. '500-599'. Applied after --accept-status and before the built-in rule") { |v| options.dead_status = v }
        parser.on("--exclude-status=LIST", "Alias of --dead-status") { |v| options.dead_status = v }
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
        parser.on("--check-anchors", "Verify #fragment targets exist in the linked document") { options.check_anchors = true }
        parser.on("--coverage", "Enable coverage tracking and reporting") { options.coverage = true }
        # The literal 2 is `Deadfinder::EXIT_DEAD_FOUND`. Spelled out rather than
        # interpolated so `Completion::FLAGS` can mirror this line verbatim and its
        # drift spec stays an exact comparison.
        parser.on("-F", "--fail-on-dead", "Exit with code 2 when any dead link or dead target is found (default: always exit 0)") { options.fail_on_dead = true }
        parser.on("--visualize=PATH", "Generate visualization PNG") { |v| options.visualize = v }
        parser.on("-h", "--help", "Show help") do
          puts parser
          exit
        end

        parser.unknown_args do |remaining, _|
          if remaining.size > 0
            subcommand = remaining[0]
            positional_arg = remaining[1]? if remaining.size > 1
            extra_args = remaining[2..] if remaining.size > 2
          end
        end
      end

      begin
        global_parser.parse(args)
      rescue ex : OptionParser::Exception | ArgumentError
        STDERR.puts "Error: #{ex.message}"
        exit 1
      end

      # Reject arguments the chosen subcommand cannot use instead of silently
      # dropping them: `deadfinder file a.txt b.txt` used to scan only a.txt,
      # and `deadfinder pipe urls.txt` used to ignore the file entirely and then
      # block on an empty STDIN.
      leftover = extra_args.dup
      if (arg = positional_arg) && subcommand && ["pipe", "version"].includes?(subcommand)
        leftover.unshift(arg)
      end
      unless leftover.empty?
        STDERR.puts "Error: unexpected argument#{leftover.size > 1 ? "s" : ""} for `#{subcommand}`: #{leftover.join(" ")}"
        exit 1
      end

      # Validate numeric and enum options up front so invalid values fail fast
      # with a clear message rather than hanging or silently misbehaving. Only
      # the scanning subcommands consume these, so `version`/`completion` aren't
      # rejected for an (irrelevant) bad option value.
      if subcommand && ["pipe", "file", "url", "sitemap"].includes?(subcommand)
        {
          {"concurrency", options.concurrency, 1},
          {"target concurrency", options.target_concurrency, 1},
          {"timeout", options.timeout, 1},
          {"limit", options.limit, 0},
          {"retry", options.retries, 0},
          {"delay", options.delay, 0},
        }.each do |(name, value, min)|
          if value < min
            STDERR.puts "Error: #{name} must be >= #{min} (got #{value})"
            exit 1
          end
        end
        unless HttpClient::METHODS.includes?(options.http_method)
          STDERR.puts "Error: unsupported method: #{options.http_method} (allowed: #{HttpClient::METHODS.join(", ")})"
          exit 1
        end
        {"match" => options.match, "ignore" => options.ignore}.each do |name, pattern|
          next if pattern.empty?
          begin
            UrlPatternMatcher.validate!(pattern)
          rescue ex : ArgumentError
            STDERR.puts "Error: invalid #{name} pattern: #{ex.message}"
            exit 1
          end
        end
        allowed_formats = ["json", "yaml", "yml", "csv", "toml", "sarif"]
        unless allowed_formats.includes?(options.output_format.downcase)
          STDERR.puts "Error: unsupported output format: #{options.output_format} (allowed: #{allowed_formats.join(", ")})"
          exit 1
        end
      end

      # Auto-enable coverage if visualize is set
      if !options.visualize.empty?
        options.coverage = true
      end

      case subcommand
      when "pipe"
        Deadfinder.run_pipe(options)
        exit_on_findings(options)
      when "file"
        if positional_arg
          filename = positional_arg.not_nil!
          # `File.file?` is true only for regular files, which rejected every
          # legitimate non-regular source: shell process substitution
          # (`deadfinder file <(...)` -> /dev/fd/N), /dev/stdin, and named
          # pipes all reported a bogus "file not found". Check existence
          # instead, and name a directory for what it is.
          if filename != Deadfinder::STDIN_FILENAME
            if Dir.exists?(filename)
              STDERR.puts "Error: #{filename} is a directory, not a file"
              exit 1
            end
            unless File.exists?(filename)
              STDERR.puts "Error: file not found: #{filename}"
              exit 1
            end
          end
          Deadfinder.run_file(filename, options)
          exit_on_findings(options)
        else
          STDERR.puts "Error: file command requires a filename argument"
          STDERR.puts "Usage: deadfinder file <FILE> [options]  (use `-` to read from STDIN)"
          exit 1
        end
      when "url", "sitemap"
        unless target = positional_arg
          STDERR.puts "Error: #{subcommand} command requires a URL argument"
          STDERR.puts "Usage: deadfinder #{subcommand} <#{subcommand == "url" ? "URL" : "SITEMAP-URL"}> [options]"
          exit 1
        end
        if reason = Deadfinder.http_target_error(target)
          STDERR.puts "Error: #{reason}"
          exit 1
        end
        if subcommand == "url"
          Deadfinder.run_url(target, options)
        else
          Deadfinder.run_sitemap(target, options)
        end
        exit_on_findings(options)
      when "completion"
        unless shell = positional_arg
          STDERR.puts "Error: completion command requires a shell argument (bash/zsh/fish)"
          exit 1
        end
        unless ["bash", "zsh", "fish"].includes?(shell)
          Deadfinder::Logger.error "Unsupported shell: #{shell}"
          exit 1
        end
        case shell
        when "bash" then puts Deadfinder::Completion.bash
        when "zsh"  then puts Deadfinder::Completion.zsh
        when "fish" then puts Deadfinder::Completion.fish
        end
      when "version"
        Deadfinder::Logger.info "deadfinder #{Deadfinder::VERSION}"
      else
        puts global_parser
        exit 1 if subcommand
      end
    end

    # `--fail-on-dead` turns a completed scan that found something into a
    # non-zero exit so a CI job can gate on it. Opt-in only: the frozen v1
    # contract is that every scan exits 0, and `spec/compat/run.rb` asserts it.
    # Exit 1 stays reserved for usage/IO errors, so findings get their own code.
    private def self.exit_on_findings(options : Options) : Nil
      return unless options.fail_on_dead
      exit Deadfinder::EXIT_DEAD_FOUND if Deadfinder.dead_findings?
    end
  end
end
