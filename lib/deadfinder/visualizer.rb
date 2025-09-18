# frozen_string_literal: true

require 'chunky_png'

module DeadFinder
  # Visualizer module for generating images from scan results
  module Visualizer
    def self.generate(data, output_path)
      # Extract summary data
      summary = data[:summary]
      return if summary.nil?

      total_tested = summary[:total_tested]
      total_dead = summary[:total_dead]
      return if total_tested.nil? || total_dead.nil?

      # Create a new image
      png = ChunkyPNG::Image.new(500, 300, ChunkyPNG::Color::WHITE)

      # Draw progress bar representing dead links percentage
      if total_tested > 0
        percentage = (total_dead.to_f / total_tested)
        bar_width = (460 * percentage).to_i
        png.rect(20, 100, 480, 150, ChunkyPNG::Color('gray'))
        png.rect(20, 100, 20 + bar_width, 150, ChunkyPNG::Color('red'))
      end

      # Save the image
      png.save(output_path, :fast_rgba)
    end
  end
end
