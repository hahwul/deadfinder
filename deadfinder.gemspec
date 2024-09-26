require_relative 'lib/deadfinder/version'
Gem::Specification.new do |s|
  s.name = 'deadfinder'
  s.version     = VERSION
  s.summary     = 'Find dead-links (broken links)'
  s.description = 'Find dead-links (broken links). Dead link (broken link) means a link within a web page that cannot be connected. These links can have a negative impact to SEO and Security. This tool makes it easy to identify and modify.'
  s.authors     = ['hahwul']
  s.email       = 'hahwul@gmail.com'
  s.files       = ['lib/deadfinder.rb']
  s.homepage    = 'https://www.hahwul.com'
  s.license = 'MIT'
  s.executables << 'deadfinder'
  s.files = ['lib/deadfinder.rb', 'lib/deadfinder/utils.rb', 'lib/deadfinder/logger.rb', 'lib/deadfinder/version.rb']
  s.metadata['rubygems_mfa_required'] = 'true'
  s.metadata['source_code_uri'] = 'https://github.com/hahwul/deadfinder'
  s.add_runtime_dependency 'colorize', '~> 0.8.0', '>= 0.8.0'
  s.add_runtime_dependency 'concurrent-ruby-edge', '~> 0.6.0', '>= 0.6.0'
  s.add_runtime_dependency 'json', '~> 2.6.0', '>= 2.6.0'
  s.add_runtime_dependency 'nokogiri', '~> 1.13.0', '>= 1.13.0'
  s.add_runtime_dependency 'open-uri', '~> 0.2.0', '>= 0.2.0'
  s.add_runtime_dependency 'set', '~> 1.1.0', '>= 1.1.0'
  s.add_runtime_dependency 'sitemap-parser', '~> 0.5.0', '>= 0.5.0'
  s.add_runtime_dependency 'thor', '~> 1.2.0', '>= 1.2.0'
end
