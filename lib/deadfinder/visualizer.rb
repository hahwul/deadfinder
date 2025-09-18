# frozen_string_literal: true

require 'chunky_png'

module DeadFinder
  # Visualizer module for generating images from scan results
  module Visualizer
    def self.generate(data, output_path)
      # Extract summary data
      summary = data.dig(:summary)
      return if summary.nil?

      total_tested = summary.dig(:total_tested)
      total_dead = summary.dig(:total_dead)
      return if total_tested.nil? || total_dead.nil?

      # Create a new image
      png = ChunkyPNG::Image.new(500, 300, ChunkyPNG::Color::WHITE)

      # Draw title
      png.compose!(ChunkyPNG::Image.from_text('DeadFinder Scan Report', 40, color: ChunkyPNG::Color::BLACK), 20, 20)

      # Draw stats
      png.compose!(ChunkyPNG::Image.from_text("Total URLs Tested: #{total_tested}", 20, color: ChunkyPNG::Color::BLACK), 20, 80)
      png.compose!(ChunkyPNG::Image.from_text("Dead Links Found: #{total_dead}", 20, color: ChunkyPNG::Color('red')), 20, 110)

      # Draw progress bar
      if total_tested > 0
        percentage = (total_dead.to_f / total_tested)
        bar_width = (460 * percentage).to_i
        png.rect(20, 150, 480, 200, ChunkyPNG::Color('gray'))
        png.rect(20, 150, 20 + bar_width, 200, ChunkyPNG::Color('red'))
      end

      # Draw project info
      png.compose!(ChunkyPNG::Image.from_text('github.com/hahwul/deadfinder', 10, color: ChunkyPNG::Color::BLACK), 20, 270)


      # Save the image
      png.save(output_path, :fast_rgba)
    end
  end
end
