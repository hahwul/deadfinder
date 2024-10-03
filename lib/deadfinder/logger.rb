# frozen_string_literal: true

require 'colorize'

class Logger
  @silent = false

  def self.set_silent
    @silent = true
  end

  def self.silent?
    @silent
  end

  def self.info(text)
    puts 'ℹ '.colorize(:blue) + text.to_s.colorize(:light_blue) unless silent?
  end

  def self.error(text)
    puts '⚠︎ '.colorize(:red) + text.to_s unless silent?
  end

  def self.target(text)
    puts '► '.colorize(:green) + text.to_s.colorize(:light_green) unless silent?
  end

  def self.sub_info(text)
    puts '  ● '.colorize(:blue) + text.to_s.colorize(:light_blue) unless silent?
  end

  def self.sub_done(text)
    puts '  ✓ '.colorize(:blue) + text.to_s.colorize(:light_blue) unless silent?
  end

  def self.found(text)
    puts "  ✘ #{text}".colorize(:red) unless silent?
  end

  def self.verbose(text)
    puts '  ➜ '.colorize(:yellow) + text.to_s.colorize(:light_yellow) unless silent?
  end
end
