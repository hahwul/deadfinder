# frozen_string_literal: true

require 'colorize'

class Logger
  @silent = false
  @mutex = Mutex.new

  def self.set_silent
    @mutex.synchronize { @silent = true }
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
    log('✓ ', text, :green)
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
    sub_log('➜ ', false, text, :yellow)
  end

  def self.verbose_ok(text)
    sub_log('✓ ', false, text, :green)
  end
end
