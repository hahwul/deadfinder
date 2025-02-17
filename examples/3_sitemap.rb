# frozen_string_literal: true

require 'deadfinder'

runner = DeadFinder::Runner.new
options = runner.default_options
options['concurrency'] = 30

DeadFinder.run_sitemap('https://dalfox.hahwul.com/sitemap.xml', options)
puts DeadFinder.output
