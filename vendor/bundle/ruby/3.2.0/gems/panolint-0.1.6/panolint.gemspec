# frozen_string_literal: true

lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "panolint/version"

Gem::Specification.new do |spec|
  spec.name          = "panolint"
  spec.version       = Panolint::VERSION
  spec.authors       = ["Kevin Deisz"]
  spec.email         = ["kevin.deisz@gmail.com"]

  spec.summary       = "Rules for linting code at Panorama Education"
  spec.homepage      = "https://github.com/panorama-ed/panolint"
  spec.license       = "MIT"
  spec.metadata      = { "rubygems_mfa_required" => "true" }

  spec.files         = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject do |f|
      f.match(%r{^(test|spec|features)/})
    end
  end

  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "brakeman", ">= 4.8", "< 6.0"
  spec.add_dependency "rubocop", ">= 0.83", "< 2.0"
  spec.add_dependency "rubocop-performance", "~> 1.5"
  spec.add_dependency "rubocop-rails", "~> 2.5"
  spec.add_dependency "rubocop-rake", "~> 0.5"
  spec.add_dependency "rubocop-rspec", "~> 2.0"

  spec.add_development_dependency "bundler", "~> 2.1"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
end
