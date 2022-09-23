require 'thor'
require 'open-uri'
require 'nokogiri'

def run_pipe
  while STDIN.gets
    target = $_.gsub("\n",'')
    page = Nokogiri::HTML(URI.open(target))
    nodeset = page.css('a')
    link_a = nodeset.map {|element| element["href"]}.compact
    puts link_a
  end
end

class DeadFinder < Thor
  desc "pipe", "URLs from STDIN (e.g cat urls.txt | deadfinder pipe)"
  def pipe
    puts "pipe mode"
    run_pipe
  end
end