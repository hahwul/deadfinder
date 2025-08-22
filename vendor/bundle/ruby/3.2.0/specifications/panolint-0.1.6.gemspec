# -*- encoding: utf-8 -*-
# stub: panolint 0.1.6 ruby lib

Gem::Specification.new do |s|
  s.name = "panolint".freeze
  s.version = "0.1.6"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "rubygems_mfa_required" => "true" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Kevin Deisz".freeze]
  s.bindir = "exe".freeze
  s.date = "2022-10-19"
  s.email = ["kevin.deisz@gmail.com".freeze]
  s.homepage = "https://github.com/panorama-ed/panolint".freeze
  s.licenses = ["MIT".freeze]
  s.rubygems_version = "3.4.20".freeze
  s.summary = "Rules for linting code at Panorama Education".freeze

  s.installed_by_version = "3.4.20" if s.respond_to? :installed_by_version

  s.specification_version = 4

  s.add_runtime_dependency(%q<brakeman>.freeze, [">= 4.8", "< 6.0"])
  s.add_runtime_dependency(%q<rubocop>.freeze, [">= 0.83", "< 2.0"])
  s.add_runtime_dependency(%q<rubocop-performance>.freeze, ["~> 1.5"])
  s.add_runtime_dependency(%q<rubocop-rails>.freeze, ["~> 2.5"])
  s.add_runtime_dependency(%q<rubocop-rake>.freeze, ["~> 0.5"])
  s.add_runtime_dependency(%q<rubocop-rspec>.freeze, ["~> 2.0"])
  s.add_development_dependency(%q<bundler>.freeze, ["~> 2.1"])
  s.add_development_dependency(%q<rake>.freeze, ["~> 13.0"])
  s.add_development_dependency(%q<rspec>.freeze, ["~> 3.0"])
end
