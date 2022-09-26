# frozen_string_literal: true

require 'colorize'

class Logger
  def self.info(text)
    puts 'ℹ '.colorize(:blue) + text.to_s.colorize(:light_blue)
  end

  def self.target(text)
    puts '► '.colorize(:green) + text.to_s.colorize(:light_green)
  end

  def self.sub_info(text)
    puts '  ● '.colorize(:blue) + text.to_s.colorize(:light_blue)
  end

  def self.sub_done(text)
    puts '  ✓ '.colorize(:blue) + text.to_s.colorize(:light_blue)
  end

  def self.found(text)
    puts "  ✘ #{text}".colorize(:red)
  end
end
