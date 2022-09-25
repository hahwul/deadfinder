# frozen_string_literal: true

require_relative 'lib/deadfinder/version'

Gem::Specification.new do |s|
  s.name = 'deadfinder'
  s.version     = VERSION
  s.summary     = 'Find dead-links (broken links)'
  s.description = 'Find dead-links (broken links)'
  s.authors     = ['hahwul']
  s.email       = 'hahwul@gmail.com'
  s.files       = ['lib/deadfinder.rb']
  s.homepage    = 'https://www.hahwul.com'
  s.license = 'MIT'
  s.executables << 'deadfinder'
  s.files = ['lib/deadfinder.rb', 'lib/deadfinder/utils.rb', 'lib/deadfinder/logger.rb', 'lib/deadfinder/version.rb']
  s.metadata['rubygems_mfa_required'] = 'true'
  s.metadata['source_code_uri'] = 'https://github.com/hahwul/deadfinder'
end
