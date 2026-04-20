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
      case color
      when :yellow
        print prefix.colorize(:yellow)
      when :blue
        print prefix.colorize(:blue)
      when :red
        print prefix.colorize(:red)
      when :green
        print prefix.colorize(:green)
      else
        print prefix
      end
      puts text
    end

    def self.sub_log(prefix : String, is_end : Bool, text : String, color : Symbol)
      return if silent?
      indent = is_end ? "  \u2514\u2500\u2500 " : "  \u251C\u2500\u2500 "
      case color
      when :yellow
        print indent.colorize(:yellow)
        print prefix.colorize(:yellow)
      when :blue
        print indent.colorize(:blue)
        print prefix.colorize(:blue)
      when :red
        print indent.colorize(:red)
        print prefix.colorize(:red)
      when :green
        print indent.colorize(:green)
        print prefix.colorize(:green)
      else
        print indent
        print prefix
      end
      puts text
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
