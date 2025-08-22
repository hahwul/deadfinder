# -*- encoding: utf-8 -*-
# stub: concurrent-ruby-edge 0.7.2 ruby lib/concurrent-ruby-edge

Gem::Specification.new do |s|
  s.name = "concurrent-ruby-edge".freeze
  s.version = "0.7.2"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib/concurrent-ruby-edge".freeze]
  s.authors = ["Jerry D'Antonio".freeze, "Petr Chalupa".freeze, "The Ruby Concurrency Team".freeze]
  s.date = "2025-01-15"
  s.description = "These features are under active development and may change frequently. They are expected not to\nkeep backward compatibility (there may also lack tests and documentation). Semantic versions will\nbe obeyed though. Features developed in `concurrent-ruby-edge` are expected to move to `concurrent-ruby` when final.\nPlease see http://concurrent-ruby.com for more information.\n".freeze
  s.email = "concurrent-ruby@googlegroups.com".freeze
  s.extra_rdoc_files = ["README.md".freeze, "LICENSE.txt".freeze, "CHANGELOG.md".freeze]
  s.files = ["CHANGELOG.md".freeze, "LICENSE.txt".freeze, "README.md".freeze]
  s.homepage = "http://www.concurrent-ruby.com".freeze
  s.licenses = ["MIT".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.3".freeze)
  s.rubygems_version = "3.4.20".freeze
  s.summary = "Edge features and additions to the concurrent-ruby gem.".freeze

  s.installed_by_version = "3.4.20" if s.respond_to? :installed_by_version

  s.specification_version = 4

  s.add_runtime_dependency(%q<concurrent-ruby>.freeze, ["~> 1.3"])
end
