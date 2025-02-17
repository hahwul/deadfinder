# frozen_string_literal: true

require 'deadfinder'

runner = DeadFinder::Runner.new
options = runner.default_options
options['concurrency'] = 30

DeadFinder.run_url('https://www.hahwul.com/cullinan/csrf/', options)
puts DeadFinder.output
