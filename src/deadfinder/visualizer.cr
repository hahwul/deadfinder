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

      # An unwritable --visualize path must not crash the run after the scan
      # has already completed and (optionally) the report has been written.
      begin
        StumpyPNG.write(canvas, output_path)
      rescue ex : IO::Error
        Deadfinder::Logger.error "Failed to write visualization to #{output_path}: #{ex.message}"
      end
    end

    private def self.status_color(status : String) : StumpyPNG::RGBA
      case status
      when "200"
        StumpyPNG::RGBA.from_rgb8(0, 255, 0) # Green
      when /^3\d{2}$/
        StumpyPNG::RGBA.from_rgb8(255, 165, 0) # Orange
      when /^4\d{2}$/
        StumpyPNG::RGBA.from_rgb8(255, 0, 0) # Red
      when /^5\d{2}$/
        StumpyPNG::RGBA.from_rgb8(128, 0, 128) # Purple
      else
        StumpyPNG::RGBA.from_rgb8(128, 128, 128) # Gray
      end
    end

    private def self.draw_corners(canvas, x1, y1, x2, y2, r, color)
      # One quarter circle per corner: its centre and the angles it sweeps.
      {
        {x1 + r, y1 + r, 0..90},    # top-left
        {x2 - r, y1 + r, 90..180},  # top-right
        {x1 + r, y2 - r, 270..360}, # bottom-left
        {x2 - r, y2 - r, 180..270}, # bottom-right
      }.each do |(cx, cy, angles)|
        angles.each do |angle|
          rad = angle * Math::PI / 180
          px = (cx + r * Math.cos(rad)).to_i
          py = (cy + r * Math.sin(rad)).to_i
          canvas[px, py] = color if x1 <= px <= x2 && y1 <= py <= y2
        end
      end
    end
  end
end
