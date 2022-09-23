# frozen_string_literal: true

require 'English'
require 'thor'
require 'open-uri'
require 'nokogiri'
require 'deadfinder/utils'
require 'concurrent-edge'

Channel = Concurrent::Channel

class DeadFinderRunner
  def run(target)
    page = Nokogiri::HTML(URI.open(target))
    nodeset = page.css('a')
    link_a = nodeset.map { |element| element['href'] }.compact
    puts target
    jobs    = Channel.new(buffer: :buffered, capacity: 100)
    results = Channel.new(buffer: :buffered, capacity: 100)

    (1..20).each do |w|
      Channel.go { worker(w, jobs, results) }
    end

    link_a.uniq.each do |node|
      result = generate_url node, target
      jobs << result
    end
    jobs.close

    (1..link_a.uniq.length).each do 
      ~results
    end
  end

  def worker(id, jobs, results)
    jobs.each do |j|
      begin
        URI.open(j)
      rescue => exception
        puts " ㄴ [#{exception}] #{j}"
      end  
      results << j
    end
  end
end

def run_pipe
  app = DeadFinderRunner.new
  while $stdin.gets
    target = $LAST_READ_LINE.gsub("\n", '')
    app.run target
  end
end

def run_file(filename)
  app = DeadFinderRunner.new
  File.open(filename).each do |line|
    target = line.gsub("\n", '')
    app.run target
  end
end

def run_url(url)
  app = DeadFinderRunner.new
  app.run url
end

class DeadFinder < Thor
  desc 'pipe', 'URLs from STDIN (e.g cat urls.txt | deadfinder pipe)'
  def pipe
    puts 'pipe mode'
    run_pipe
  end

  desc 'file', 'URLs from File (e.g deadfinder file urls.txt)'
  def file(filename)
    puts 'file mode'
    run_file filename
  end

  desc 'url', 'Single URL'
  def url(url)
    puts 'url mode'
    run_url url
  end
end
