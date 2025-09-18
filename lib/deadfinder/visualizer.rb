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
      return if total_tested.nil? || total_tested.zero?

      # Create a new image with transparent background
      png = ChunkyPNG::Image.new(500, 300, ChunkyPNG::Color::TRANSPARENT)

      # Draw stacked bar chart for status code distribution
      status_counts = data[:summary][:overall_status_counts] || {}
      bar_height = 70
      current_y = 110

      # Sort statuses by count descending
      sorted_statuses = status_counts.sort_by { |_, v| -v }

      sorted_statuses.each do |status, count|
        height = (count.to_f / total_tested * bar_height).to_i
        next if height.zero?

        color = case status.to_s
                when '200' then ChunkyPNG::Color.rgb(0, 255, 0) # Green for 200
                when /^3\d{2}$/ then ChunkyPNG::Color.rgb(255, 165, 0) # Orange for 3xx
                when /^4\d{2}$/ then ChunkyPNG::Color.rgb(255, 0, 0)   # Red for 4xx
                when /^5\d{2}$/ then ChunkyPNG::Color.rgb(128, 0, 128) # Purple for 5xx
                else ChunkyPNG::Color.rgb(128, 128, 128)               # Gray for others/error
                end

        (current_y..(current_y + height - 1)).each do |y|
          (20..480).each do |x|
            png[x, y] = color
          end
        end
        current_y += height
      end

      # Draw rounded outline around the bar area
      r = 10
      x1 = 10
      y1 = 100
      x2 = 490
      y2 = 190

      # Top line
      ((x1 + r)..(x2 - r)).each do |x|
        png[x, y1] = ChunkyPNG::Color.rgba(0, 0, 0, 128)
        # Bottom line
        png[x, y2] = ChunkyPNG::Color.rgba(0, 0, 0, 128)
      end
      # Left line
      ((y1 + r)..(y2 - r)).each do |y|
        png[x1, y] = ChunkyPNG::Color.rgba(0, 0, 0, 128)
        # Right line
        png[x2, y] = ChunkyPNG::Color.rgba(0, 0, 0, 128)
      end

      # Corners: quarter circles
      # Top-left
      (0..90).each do |angle|
        rad = angle * Math::PI / 180
        cx = x1 + r
        cy = y1 + r
        px = cx + (r * Math.cos(rad))
        py = cy + (r * Math.sin(rad))
        png[px.to_i, py.to_i] = ChunkyPNG::Color.rgba(0, 0, 0, 128) if px >= x1 && py >= y1
      end
      # Top-right
      (90..180).each do |angle|
        rad = angle * Math::PI / 180
        cx = x2 - r
        cy = y1 + r
        px = cx + (r * Math.cos(rad))
        py = cy + (r * Math.sin(rad))
        png[px.to_i, py.to_i] = ChunkyPNG::Color.rgba(0, 0, 0, 128) if px <= x2 && py >= y1
      end
      # Bottom-left
      (270..360).each do |angle|
        rad = angle * Math::PI / 180
        cx = x1 + r
        cy = y2 - r
        px = cx + (r * Math.cos(rad))
        py = cy + (r * Math.sin(rad))
        png[px.to_i, py.to_i] = ChunkyPNG::Color.rgba(0, 0, 0, 128) if px >= x1 && py <= y2
      end
      # Bottom-right
      (180..270).each do |angle|
        rad = angle * Math::PI / 180
        cx = x2 - r
        cy = y2 - r
        px = cx + (r * Math.cos(rad))
        py = cy + (r * Math.sin(rad))
        png[px.to_i, py.to_i] = ChunkyPNG::Color.rgba(0, 0, 0, 128) if px <= x2 && py <= y2
      end

      # Save the image
      png.save(output_path, :fast_rgba)
    end
  end
end
