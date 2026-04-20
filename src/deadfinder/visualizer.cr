require "stumpy_png"

module Deadfinder
  module Visualizer
    def self.generate(data : CoverageResult, output_path : String)
      summary = data.summary
      total_tested = summary.total_tested
      return if total_tested == 0

      canvas = StumpyPNG::Canvas.new(500, 300)

      # Draw stacked bar chart for status code distribution
      status_counts = summary.overall_status_counts
      bar_height = 70
      current_y = 110

      # Sort statuses by count descending
      sorted_statuses = status_counts.to_a.sort_by { |_, v| -v }

      sorted_statuses.each do |status, count|
        height = (count.to_f / total_tested * bar_height).to_i
        next if height == 0

        color = status_color(status)

        (current_y...(current_y + height)).each do |y|
          (20..480).each do |x|
            canvas[x, y] = color
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
      outline = StumpyPNG::RGBA.new(0_u16, 0_u16, 0_u16, 32768_u16) # semi-transparent black

      # Top and bottom lines
      ((x1 + r)..(x2 - r)).each do |x|
        canvas[x, y1] = outline
        canvas[x, y2] = outline
      end

      # Left and right lines
      ((y1 + r)..(y2 - r)).each do |y|
        canvas[x1, y] = outline
        canvas[x2, y] = outline
      end

      # Corners: quarter circles
      draw_corners(canvas, x1, y1, x2, y2, r, outline)

      StumpyPNG.write(canvas, output_path)
    end

    private def self.status_color(status : String) : StumpyPNG::RGBA
      case status
      when "200"
        StumpyPNG::RGBA.from_rgb8(0, 255, 0)       # Green
      when /^3\d{2}$/
        StumpyPNG::RGBA.from_rgb8(255, 165, 0)     # Orange
      when /^4\d{2}$/
        StumpyPNG::RGBA.from_rgb8(255, 0, 0)       # Red
      when /^5\d{2}$/
        StumpyPNG::RGBA.from_rgb8(128, 0, 128)     # Purple
      else
        StumpyPNG::RGBA.from_rgb8(128, 128, 128)   # Gray
      end
    end

    private def self.draw_corners(canvas, x1, y1, x2, y2, r, color)
      # Top-left
      (0..90).each do |angle|
        rad = angle * Math::PI / 180
        cx = x1 + r
        cy = y1 + r
        px = (cx + r * Math.cos(rad)).to_i
        py = (cy + r * Math.sin(rad)).to_i
        canvas[px, py] = color if px >= x1 && py >= y1
      end

      # Top-right
      (90..180).each do |angle|
        rad = angle * Math::PI / 180
        cx = x2 - r
        cy = y1 + r
        px = (cx + r * Math.cos(rad)).to_i
        py = (cy + r * Math.sin(rad)).to_i
        canvas[px, py] = color if px <= x2 && py >= y1
      end

      # Bottom-left
      (270..360).each do |angle|
        rad = angle * Math::PI / 180
        cx = x1 + r
        cy = y2 - r
        px = (cx + r * Math.cos(rad)).to_i
        py = (cy + r * Math.sin(rad)).to_i
        canvas[px, py] = color if px >= x1 && py <= y2
      end

      # Bottom-right
      (180..270).each do |angle|
        rad = angle * Math::PI / 180
        cx = x2 - r
        cy = y2 - r
        px = (cx + r * Math.cos(rad)).to_i
        py = (cy + r * Math.sin(rad)).to_i
        canvas[px, py] = color if px <= x2 && py <= y2
      end
    end
  end
end
