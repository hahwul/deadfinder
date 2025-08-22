# -*- encoding: utf-8 -*-
# stub: simplecov-cobertura 2.1.0 ruby lib

Gem::Specification.new do |s|
  s.name = "simplecov-cobertura".freeze
  s.version = "2.1.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Jesse Bowes".freeze]
  s.date = "2021-12-14"
  s.description = "Produces Cobertura XML formatted output from SimpleCov".freeze
  s.email = ["jbowes@dashingrocket.com".freeze]
  s.homepage = "https://github.com/dashingrocket/simplecov-cobertura".freeze
  s.licenses = ["Apache-2.0".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.5.0".freeze)
  s.rubygems_version = "3.4.20".freeze
  s.summary = "SimpleCov Cobertura Formatter".freeze

  s.installed_by_version = "3.4.20" if s.respond_to? :installed_by_version

  s.specification_version = 4

  s.add_development_dependency(%q<test-unit>.freeze, ["~> 3.2"])
  s.add_development_dependency(%q<nokogiri>.freeze, ["~> 1.0"])
  s.add_development_dependency(%q<rake>.freeze, ["~> 13.0"])
  s.add_runtime_dependency(%q<simplecov>.freeze, ["~> 0.19"])
  s.add_runtime_dependency(%q<rexml>.freeze, [">= 0"])
end
