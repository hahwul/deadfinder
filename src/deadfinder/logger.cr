require "colorize"

module Deadfinder
  module Logger
    @@silent = false
    @@verbose = false
    @@debug = false
    @@mutex = Mutex.new

    def self.apply_options(options : Options)
      set_silent if options.silent
      set_verbose if options.verbose
      set_debug if options.debug
    end

    def self.set_silent
      @@mutex.synchronize { @@silent = true }
    end

    def self.unset_silent
      @@mutex.synchronize { @@silent = false }
    end

    def self.silent?
      @@mutex.synchronize { @@silent }
    end

    def self.set_verbose
      @@mutex.synchronize { @@verbose = true }
    end

    def self.unset_verbose
      @@mutex.synchronize { @@verbose = false }
    end

    def self.verbose?
      @@mutex.synchronize { @@verbose }
    end

    def self.set_debug
      @@mutex.synchronize { @@debug = true }
    end

    def self.unset_debug
      @@mutex.synchronize { @@debug = false }
    end

    def self.debug?
      @@mutex.synchronize { @@debug }
    end

    def self.log(prefix : String, text : String, color : Symbol)
      return if silent?
      line = String.build do |io|
        case color
        when :yellow
          io << prefix.colorize(:yellow)
        when :blue
          io << prefix.colorize(:blue)
        when :red
          io << prefix.colorize(:red)
        when :green
          io << prefix.colorize(:green)
        else
          io << prefix
        end
        io << text
        io << '\n'
      end
      print_line(line)
    end

    def self.sub_log(prefix : String, is_end : Bool, text : String, color : Symbol)
      return if silent?
      indent = is_end ? "  \u2514\u2500\u2500 " : "  \u251C\u2500\u2500 "
      line = String.build do |io|
        case color
        when :yellow
          io << indent.colorize(:yellow)
          io << prefix.colorize(:yellow)
        when :blue
          io << indent.colorize(:blue)
          io << prefix.colorize(:blue)
        when :red
          io << indent.colorize(:red)
          io << prefix.colorize(:red)
        when :green
          io << indent.colorize(:green)
          io << prefix.colorize(:green)
        else
          io << indent
          io << prefix
        end
        io << text
        io << '\n'
      end
      print_line(line)
    end

    # Centralized writer. A closed/broken output stream (e.g. STDOUT piped to a
    # process that exited, like `... | head`) raises IO::Error; swallow it so
    # logging can never crash a scan or leave the worker accounting unbalanced.
    private def self.print_line(line : String)
      @@mutex.synchronize do
        begin
          STDOUT.print line
        rescue IO::Error
        end
      end
    end

    def self.debug(text : String)
      log("\u2740 ", text, :yellow) if debug?
    end

    def self.info(text : String)
      log("\u2139 ", text, :blue)
    end

    def self.error(text : String)
      log("\u26A0\uFE0E ", text, :red)
    end

    def self.target(text : String)
      log("\u25BA ", text, :green)
    end

    def self.sub_info(text : String)
      log("  \u25CF ", text, :blue)
    end

    def self.sub_complete(text : String)
      sub_log("\u25CF ", true, text, :blue)
    end

    def self.found(text : String)
      sub_log("\u2718 ", false, text, :red)
    end

    def self.verbose(text : String)
      sub_log("\u279C ", false, text, :yellow) if verbose?
    end

    def self.verbose_ok(text : String)
      sub_log("\u2713 ", false, text, :green) if verbose?
    end
  end
end
