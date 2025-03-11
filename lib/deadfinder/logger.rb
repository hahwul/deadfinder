# frozen_string_literal: true

require 'colorize'

module DeadFinder
  class Logger
    @silent = false
    @verbose = false
    @debug = false
    @mutex = Mutex.new

    def self.apply_options(options)
      set_silent if options['silent']
      set_verbose if options['verbose']
      set_debug if options['debug']
    end

    def self.set_silent
      @mutex.synchronize { @silent = true }
    end

    def self.set_verbose
      @mutex.synchronize { @verbose = true }
    end

    def self.set_debug
      @mutex.synchronize { @debug = true }
    end

    def self.unset_debug
      @mutex.synchronize { @debug = false }
    end

    def self.unset_verbose
      @mutex.synchronize { @verbose = false }
    end

    def self.debug?
      @mutex.synchronize { @debug }
    end

    def self.verbose?
      @mutex.synchronize { @verbose }
    end

    def self.unset_silent
      @mutex.synchronize { @silent = false }
    end

    def self.silent?
      @mutex.synchronize { @silent }
    end

    def self.log(prefix, text, color)
      return if silent?

      puts prefix.colorize(color) + text.to_s
    end

    def self.sub_log(prefix, is_end, text, color)
      return if silent?

      indent = is_end ? '  └── ' : '  ├── '
      puts indent.colorize(color) + prefix.colorize(color) + text.to_s
    end

    def self.debug(text)
      log('❀ ', text, :yellow) if debug?
    end

    def self.info(text)
      log('ℹ ', text, :blue)
    end

    def self.error(text)
      log('⚠︎ ', text, :red)
    end

    def self.target(text)
      log('► ', text, :green)
    end

    def self.sub_info(text)
      log('  ● ', text, :blue)
    end

    def self.sub_complete(text)
      sub_log('● ', true, text, :blue)
    end

    def self.found(text)
      sub_log('✘ ', false, text, :red)
    end

    def self.verbose(text)
      sub_log('➜ ', false, text, :yellow) if verbose?
    end

    def self.verbose_ok(text)
      sub_log('✓ ', false, text, :green) if verbose?
    end
  end
end
