# frozen_string_literal: true

require 'English'
require 'thor'
require 'open-uri'
require 'nokogiri'
require 'deadfinder/utils'

def run_pipe
  while $stdin.gets
    target = $LAST_READ_LINE.gsub("\n", '')
    page = Nokogiri::HTML(URI.open(target))
    nodeset = page.css('a')
    link_a = nodeset.map { |element| element['href'] }.compact
    link_a.each do |node|
      result = generate_url node, target
      puts result
    end
  end
end

class DeadFinder < Thor
  desc 'pipe', 'URLs from STDIN (e.g cat urls.txt | deadfinder pipe)'
  def pipe
    puts 'pipe mode'
    run_pipe
  end
end
