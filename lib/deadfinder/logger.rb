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

    puts prefix.colorize(color) + text.to_s.colorize(:"light_#{color}")
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

  def self.sub_done(text)
    log('  ✓ ', text, :blue)
  end

  def self.found(text)
    log('  ✘ ', text, :red)
  end

  def self.verbose(text)
    log('  ➜ ', text, :yellow)
  end
end
