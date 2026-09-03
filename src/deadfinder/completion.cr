module Deadfinder
  # Shell completion generators.
  #
  # The `OptionParser` block in `cli.cr` is the single source of truth for the
  # CLI surface; `FLAGS` below mirrors it. The entries store the raw
  # `parser.on(...)` arguments rather than pre-split names so that teaching the
  # completions about a new flag is a copy-paste of that line, and
  # `spec/deadfinder/completion_spec.cr` scrapes the parser back out of the
  # source to fail loudly the moment the two drift apart.
  module Completion
    # Subcommands `cli.cr` dispatches on, with the blurb from their
    # `parser.separator` lines.
    SUBCOMMANDS = [
      {"pipe", "Scan the URLs from STDIN"},
      {"file", "Scan the URLs from File (`-` for STDIN)"},
      {"url", "Scan the Single URL"},
      {"sitemap", "Scan the URLs from sitemap"},
      {"completion", "Generate completion script (bash/zsh/fish)"},
      {"version", "Show version"},
    ]

    # Shells accepted by `completion <SHELL>`.
    SHELLS = %w[bash zsh fish]

    # Formats accepted by `--output_format`. `yml` is also accepted by cli.cr's
    # validation as a silent alias of `yaml`, so it is deliberately not offered
    # here — one canonical spelling per format.
    OUTPUT_FORMATS = %w[json yaml toml csv sarif]

    # One `parser.on(...)` call, verbatim: the short spec (nil when the option
    # has no short form), the long spec, and the help text.
    record Flag, short : String?, long : String, desc : String do
      # "-c CONCURRENCY" -> "-c"; nil when there is no short form.
      def short_name : String?
        if spec = short
          spec.split(' ', 2)[0]
        end
      end

      # "--concurrency=CONCURRENCY" -> "--concurrency"
      def long_name : String
        long.split('=', 2)[0]
      end

      # The value placeholder, taken from whichever spelling carries it:
      # "-c CONCURRENCY" / "--concurrency=CONCURRENCY" -> "CONCURRENCY".
      # nil for plain switches.
      def value_name : String?
        if placeholder = long.split('=', 2)[1]?
          placeholder
        elsif spec = short
          spec.split(' ', 2)[1]?
        end
      end

      def takes_value? : Bool
        !value_name.nil?
      end

      # Every spelling, short first, matching the order `--help` prints them.
      def names : Array(String)
        if abbrev = short_name
          [abbrev, long_name]
        else
          [long_name]
        end
      end
    end

    FLAGS = [
      Flag.new("-r", "--include30x", "Include 30x redirections"),
      Flag.new("-c CONCURRENCY", "--concurrency=CONCURRENCY", "Number of concurrency (default: 50)"),
      Flag.new(nil, "--target-concurrency=N", "Number of targets scanned in parallel; total in-flight requests stay capped at -c (default: 10)"),
      Flag.new("-t TIMEOUT", "--timeout=TIMEOUT", "Timeout in seconds (default: 10)"),
      Flag.new(nil, "--method=METHOD", "Link check method: auto, head, get (default: auto). auto sends HEAD first and re-checks with GET on any 4xx/5xx (405/501 included), so no link is reported dead on a HEAD status alone. A HEAD that never reached the host is not re-checked"),
      Flag.new(nil, "--retry=N", "Retry a transient failure N times: connection error, timeout, 429 or 5xx. A 404 is never retried (default: 2)"),
      Flag.new(nil, "--delay=MS", "Minimum milliseconds between two requests to the same host; other hosts are unaffected (default: 0)"),
      Flag.new(nil, "--accept-status=LIST", "Treat these statuses as alive, e.g. '200,204,403,999' or '400-499'. Wins over --dead-status and over the built-in >= 400 rule"),
      Flag.new(nil, "--dead-status=LIST", "Treat these statuses as dead, e.g. '500-599'. Applied after --accept-status and before the built-in rule"),
      Flag.new(nil, "--exclude-status=LIST", "Alias of --dead-status"),
      Flag.new("-o OUTPUT", "--output=OUTPUT", "File to write result"),
      Flag.new("-f FORMAT", "--output_format=FORMAT", "Output format: json, yaml, toml, csv, sarif (default: json)"),
      Flag.new("-H HEADER", "--headers=HEADER", "Custom HTTP headers for initial request"),
      Flag.new(nil, "--worker_headers=HEADER", "Custom HTTP headers for worker requests"),
      Flag.new(nil, "--user_agent=UA", "User-Agent string"),
      Flag.new("-p PROXY", "--proxy=PROXY", "Proxy server"),
      Flag.new(nil, "--proxy_auth=CREDS", "Proxy authentication (user:pass)"),
      Flag.new("-k", "--insecure", "Skip TLS certificate verification (not recommended)"),
      Flag.new("-m PATTERN", "--match=PATTERN", "Match URL pattern"),
      Flag.new("-i PATTERN", "--ignore=PATTERN", "Ignore URL pattern"),
      Flag.new("-s", "--silent", "Silent mode"),
      Flag.new("-v", "--verbose", "Verbose mode"),
      Flag.new(nil, "--debug", "Debug mode"),
      Flag.new(nil, "--limit=N", "Limit number of URLs to scan"),
      Flag.new(nil, "--check-anchors", "Verify #fragment targets exist in the linked document"),
      Flag.new(nil, "--coverage", "Enable coverage tracking and reporting"),
      Flag.new("-F", "--fail-on-dead", "Exit with code 2 when any dead link or dead target is found (default: always exit 0)"),
      Flag.new(nil, "--visualize=PATH", "Generate visualization PNG"),
      Flag.new("-h", "--help", "Show help"),
    ]

    # Value suggestions fish offers after an option, keyed by long name. A
    # value starting with `(` is a fish command substitution evaluated when the
    # user hits TAB; the numeric ranges are hints, not limits — the parser
    # accepts any integer.
    FISH_VALUE_ARGS = {
      "--concurrency"   => "(seq 1 100)",
      "--timeout"       => "(seq 1 60)",
      "--output_format" => OUTPUT_FORMATS.join(" "),
    }

    def self.bash : String
      opts = FLAGS.flat_map(&.names).join(" ")
      cmds = SUBCOMMANDS.map(&.[0]).join(" ")
      cmd_pattern = SUBCOMMANDS.map(&.[0]).join("|")
      format_pattern = spellings_of("--output_format").join("|")

      <<-BASH
      _deadfinder_completions()
      {
        local cur prev cmds opts shells formats i
        COMPREPLY=()
        cur="${COMP_WORDS[COMP_CWORD]}"
        prev="${COMP_WORDS[COMP_CWORD-1]}"
        cmds="#{cmds}"
        opts="#{opts}"
        shells="#{SHELLS.join(" ")}"
        formats="#{OUTPUT_FORMATS.join(" ")}"

        # A value completion depends only on the word before the cursor, so it
        # has to win over both the option list and the subcommand list.
        case "${prev}" in
          completion)
            COMPREPLY=( $(compgen -W "${shells}" -- "${cur}") )
            return 0
            ;;
          #{format_pattern})
            COMPREPLY=( $(compgen -W "${formats}" -- "${cur}") )
            return 0
            ;;
        esac

        if [[ "${cur}" == -* ]]; then
          COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
          return 0
        fi

        # Subcommands are only offered until one has been given: after
        # `deadfinder url ` the next word is a URL, not another subcommand.
        for (( i = 1; i < COMP_CWORD; i++ )); do
          case "${COMP_WORDS[i]}" in
            #{cmd_pattern}) return 0 ;;
          esac
        done

        COMPREPLY=( $(compgen -W "${cmds}" -- "${cur}") )
        return 0
      }
      complete -F _deadfinder_completions deadfinder
      BASH
    end

    def self.zsh : String
      commands = SUBCOMMANDS.map { |(name, desc)| "    '#{name}:#{zsh_escape(desc)}'" }.join("\n")
      specs = FLAGS.map { |flag| "    #{zsh_spec(flag)}" }.join("\n")

      <<-ZSH
      #compdef deadfinder

      _deadfinder_commands() {
        local -a commands
        commands=(
      #{commands}
        )
        _describe -t commands 'deadfinder command' commands
      }

      _deadfinder() {
        local context state state_descr line
        typeset -A opt_args
        local -a opts
        opts=(
      #{specs}
        )

        _arguments -C -s $opts '1: :_deadfinder_commands' '*:: :->args' && return 0

        case $state in
          (args)
            # Only `completion` takes an argument from a fixed set; the scan
            # subcommands take a URL or a path we cannot enumerate.
            case $line[1] in
              (completion)
                _values 'shell' #{SHELLS.join(" ")}
                ;;
            esac
            ;;
        esac
      }

      _deadfinder "$@"
      ZSH
    end

    def self.fish : String
      lines = [] of String

      # `-f` on the subcommand entries stops fish from padding the very first
      # suggestion list with every file in the cwd; it is scoped to the
      # `__fish_use_subcommand` condition, so `deadfinder file <TAB>` still
      # completes paths.
      lines << "# Subcommands, offered only until one has been given."
      SUBCOMMANDS.each do |(name, desc)|
        lines << "complete -c deadfinder -n '__fish_use_subcommand' -f -a '#{name}' -d '#{fish_escape(desc)}'"
      end

      lines << ""
      lines << "# `completion <SHELL>` accepts exactly these generators."
      lines << "complete -c deadfinder -n '__fish_seen_subcommand_from completion' -x -a '#{SHELLS.join(" ")}'"

      lines << ""
      lines << "# Options."
      FLAGS.each do |flag|
        lines << String.build do |io|
          io << "complete -c deadfinder -l " << flag.long_name.lchop("--")
          if abbrev = flag.short_name
            io << " -s " << abbrev.lchop('-')
          end
          io << " -d '" << fish_escape(flag.desc) << "'"
          if flag.takes_value?
            if choices = FISH_VALUE_ARGS[flag.long_name]?
              io << " -x -a '" << choices << "'"
            else
              io << " -r"
            end
          end
        end
      end

      lines.join("\n")
    end

    # Every spelling of one option, short first. Falls back to the long name so
    # a caller naming an option that no longer exists degrades to a harmless
    # (if useless) pattern instead of raising at completion-generation time.
    private def self.spellings_of(long_name : String) : Array(String)
      FLAGS.each do |flag|
        return flag.names if flag.long_name == long_name
      end
      [long_name]
    end

    # zsh's `_arguments` specs use `[`, `]` and `:` as structure, so any of
    # those inside a help string has to be backslash-escaped.
    private def self.zsh_escape(text : String) : String
      text.gsub(/[\\\[\]:]/) { |match| "\\#{match}" }.gsub("'", "'\\''")
    end

    private def self.fish_escape(text : String) : String
      text.gsub(/[\\']/) { |match| "\\#{match}" }
    end

    # One `_arguments` spec. An option with both spellings becomes
    # `'(-r --include30x)'{-r,--include30x}'[Include 30x redirections]'`: the
    # leading group tells zsh the two spellings exclude each other and the
    # brace expansion emits one spec per spelling. A value-taking option gets a
    # trailing `:MESSAGE:ACTION`, where an empty action means "we cannot
    # enumerate this".
    private def self.zsh_spec(flag : Flag) : String
      tail = String.build do |io|
        io << '[' << zsh_escape(flag.desc) << ']'
        if placeholder = flag.value_name
          io << ':' << zsh_escape(placeholder) << ':'
          io << '(' << OUTPUT_FORMATS.join(" ") << ')' if flag.long_name == "--output_format"
        end
      end

      if abbrev = flag.short_name
        "'(#{abbrev} #{flag.long_name})'{#{abbrev},#{flag.long_name}}'#{tail}'"
      else
        "'#{flag.long_name}#{tail}'"
      end
    end
  end
end
