# -*- encoding: utf-8 -*-
# stub: sitemap-parser 0.5.6 ruby lib

Gem::Specification.new do |s|
  s.name = "sitemap-parser".freeze
  s.version = "0.5.6"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Ben Balter".freeze]
  s.date = "2021-12-14"
  s.description = "Ruby Gem to parse sitemaps.org compliant sitemaps.".freeze
  s.email = "ben.balter@github.com".freeze
  s.homepage = "https://github.com/benbalter/sitemap-parser".freeze
  s.licenses = ["MIT".freeze]
  s.rubygems_version = "3.4.20".freeze
  s.summary = "Ruby Gem to parse sitemaps.org compliant sitemaps".freeze

  s.installed_by_version = "3.4.20" if s.respond_to? :installed_by_version

  s.specification_version = 4

  s.add_runtime_dependency(%q<nokogiri>.freeze, ["~> 1.6"])
  s.add_runtime_dependency(%q<typhoeus>.freeze, [">= 0.6", "< 2.0"])
  s.add_development_dependency(%q<minitest>.freeze, ["~> 4.7"])
  s.add_development_dependency(%q<rake>.freeze, ["~> 10.4"])
  s.add_development_dependency(%q<rubocop>.freeze, ["~> 0.80"])
  s.add_development_dependency(%q<rubocop-minitest>.freeze, ["~> 0.1"])
  s.add_development_dependency(%q<rubocop-performance>.freeze, ["~> 1.5"])
  s.add_development_dependency(%q<shoulda>.freeze, ["~> 3.5"])
  s.add_development_dependency(%q<test-unit>.freeze, ["~> 3.1"])
end
