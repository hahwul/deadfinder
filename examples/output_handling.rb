# frozen_string_literal: true

require 'deadfinder'

runner = DeadFinder::Runner.new
options = runner.default_options
options['concurrency'] = 30
options['output'] = 'examples/output_handling_output.json'
options['output_format'] = 'json'

DeadFinder.run_url('https://www.hahwul.com/cullinan/csrf/', options)
DeadFinder.gen_output(options)
