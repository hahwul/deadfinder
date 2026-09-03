require "../spec_helper"

# `cli.cr`'s `OptionParser` block is the single source of truth for DeadFinder's
# CLI surface, but the parser is built inside `CLI.run` and thrown away again,
# so there is no runtime object to reflect over. These helpers scrape it back
# out of the source: the moment a flag, subcommand, shell or output format is
# added to the parser without being added to `Deadfinder::Completion`, the
# specs below fail and point at the completion scripts (and, by extension, at
# README.md / docs / action.yml, which are kept in step with the same list).
def cli_source_lines : Array(String)
  File.read_lines(File.join(__DIR__, "..", "..", "src", "deadfinder", "cli.cr"))
end

# Every `parser.on(...)` call as `{short spec, long spec, help}` — the same
# triple `Deadfinder::Completion::Flag` stores. None of the help strings
# contain an escaped quote, so scanning for double-quoted literals recovers the
# call's arguments in order.
def cli_parser_flags : Array({String?, String, String})
  cli_source_lines.compact_map do |line|
    next unless line.includes?("parser.on(")
    args = line.scan(/"([^"]*)"/).map(&.[1])
    case args.size
    when 2 then {nil, args[0], args[1]}
    when 3 then {args[0], args[1], args[2]}
    else        nil
    end
  end
end

# The `Commands:` block of the banner, as `{name, description}`.
def cli_banner_commands : Array({String, String})
  cli_source_lines.compact_map do |line|
    next unless line.includes?("parser.separator")
    text = line.scan(/"([^"]*)"/).map(&.[1]).first?
    next unless text
    # "  file <FILE>                 Scan the URLs from File ..." — the
    # placeholder is optional and the column padding is not always even.
    if m = text.match(/\A  (\w+)(?: <[^>]*>)?\s{2,}(\S.*)\z/)
      {m[1], m[2]}
    end
  end
end

# Quoted strings on the first line of cli.cr containing *marker*.
def cli_quoted_strings_near(marker : String) : Array(String)
  line = cli_source_lines.find(&.includes?(marker))
  raise "cli.cr no longer contains #{marker.inspect}" unless line
  line.scan(/"([^"]*)"/).map(&.[1])
end

describe Deadfinder::Completion do
  describe "FLAGS" do
    it "mirrors cli.cr's OptionParser block exactly, in order" do
      table = Deadfinder::Completion::FLAGS.map { |flag| {flag.short, flag.long, flag.desc} }
      table.should eq cli_parser_flags
    end

    it "splits each option spec into its spellings and value placeholder" do
      by_long = Deadfinder::Completion::FLAGS.index_by(&.long_name)

      concurrency = by_long["--concurrency"]
      concurrency.short_name.should eq "-c"
      concurrency.long_name.should eq "--concurrency"
      concurrency.value_name.should eq "CONCURRENCY"
      concurrency.takes_value?.should be_true
      concurrency.names.should eq ["-c", "--concurrency"]

      insecure = by_long["--insecure"]
      insecure.short_name.should eq "-k"
      insecure.value_name.should be_nil
      insecure.takes_value?.should be_false

      debug = by_long["--debug"]
      debug.short_name.should be_nil
      debug.names.should eq ["--debug"]
    end
  end

  describe "SUBCOMMANDS" do
    it "matches the Commands block of cli.cr's banner" do
      Deadfinder::Completion::SUBCOMMANDS.map { |(name, desc)| {name, desc} }
        .should eq cli_banner_commands
    end
  end

  describe "SHELLS" do
    it "matches the shells `completion <SHELL>` accepts" do
      Deadfinder::Completion::SHELLS.should eq cli_quoted_strings_near(".includes?(shell)")
    end
  end

  describe "OUTPUT_FORMATS" do
    it "covers every format cli.cr accepts, except the `yml` alias of `yaml`" do
      accepted = cli_quoted_strings_near("allowed_formats =")
      (accepted - ["yml"]).sort.should eq Deadfinder::Completion::OUTPUT_FORMATS.sort
    end
  end

  describe ".bash" do
    it "offers every spelling of every flag" do
      opts = Deadfinder::Completion.bash.lines.find(&.includes?("opts=\""))
      opts.should_not be_nil
      opts.not_nil!.split('"')[1].split(' ')
        .should eq Deadfinder::Completion::FLAGS.flat_map(&.names)
    end

    it "offers the subcommands" do
      cmds = Deadfinder::Completion.bash.lines.find(&.includes?("cmds=\""))
      cmds.should_not be_nil
      cmds.not_nil!.split('"')[1].split(' ')
        .should eq Deadfinder::Completion::SUBCOMMANDS.map(&.[0])
    end

    it "completes shells after `completion` and formats after --output_format" do
      script = Deadfinder::Completion.bash
      script.should contain %(shells="#{Deadfinder::Completion::SHELLS.join(" ")}")
      script.should contain %(formats="#{Deadfinder::Completion::OUTPUT_FORMATS.join(" ")}")
      script.should contain "-f|--output_format)"
      script.should contain "complete -F _deadfinder_completions deadfinder"
    end
  end

  describe ".zsh" do
    it "declares an _arguments spec for every flag" do
      script = Deadfinder::Completion.zsh
      missing = Deadfinder::Completion::FLAGS.reject do |flag|
        if abbrev = flag.short_name
          script.includes?("{#{abbrev},#{flag.long_name}}")
        else
          script.includes?("'#{flag.long_name}[")
        end
      end
      missing.map(&.long_name).should be_empty
    end

    it "describes every subcommand" do
      script = Deadfinder::Completion.zsh
      missing = Deadfinder::Completion::SUBCOMMANDS.reject do |(name, _)|
        script.includes?("'#{name}:")
      end
      missing.map(&.[0]).should be_empty
    end

    it "completes shells after `completion` and formats after --output_format" do
      script = Deadfinder::Completion.zsh
      script.should contain "_values 'shell' #{Deadfinder::Completion::SHELLS.join(" ")}"
      script.should contain ":FORMAT:(#{Deadfinder::Completion::OUTPUT_FORMATS.join(" ")})"
    end

    it "escapes the `:` in help text so it is not read as a spec separator" do
      Deadfinder::Completion.zsh.should contain %('--proxy_auth[Proxy authentication (user\\:pass)]:CREDS:')
    end
  end

  describe ".fish" do
    it "declares every flag with its short form" do
      lines = Deadfinder::Completion.fish.lines
      missing = Deadfinder::Completion::FLAGS.reject do |flag|
        prefix = "complete -c deadfinder -l #{flag.long_name.lchop("--")}"
        if abbrev = flag.short_name
          prefix += " -s #{abbrev.lchop('-')}"
        end
        lines.any?(&.starts_with?(prefix + " "))
      end
      missing.map(&.long_name).should be_empty
    end

    it "declares every subcommand" do
      lines = Deadfinder::Completion.fish.lines
      missing = Deadfinder::Completion::SUBCOMMANDS.reject do |(name, _)|
        lines.any?(&.includes?("-n '__fish_use_subcommand' -f -a '#{name}'"))
      end
      missing.map(&.[0]).should be_empty
    end

    it "completes shells after `completion` and formats after --output_format" do
      script = Deadfinder::Completion.fish
      script.should contain "-n '__fish_seen_subcommand_from completion' -x -a '#{Deadfinder::Completion::SHELLS.join(" ")}'"
      script.should contain "-l output_format -s f "
      script.should contain "-x -a '#{Deadfinder::Completion::OUTPUT_FORMATS.join(" ")}'"
    end
  end
end
