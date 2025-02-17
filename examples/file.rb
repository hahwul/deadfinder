# frozen_string_literal: true

require 'deadfinder'

runner = DeadFinder::Runner.new
options = runner.default_options
options['concurrency'] = 30

DeadFinder.run_file('urls.txt', options)
puts DeadFinder.output
