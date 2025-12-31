# frozen_string_literal: true

require_relative 'lib/deadfinder/version'

desc 'Run tests'
task :test do
  sh 'bundle exec rspec'
end

desc 'Run linter'
task :lint do
  sh 'bundle exec rubocop'
end

desc 'Run linter and fix'
task :fix do
  sh 'bundle exec rubocop -A'
end

namespace :gem do
  desc 'Build the gem'
  task :build do
    sh 'gem build deadfinder.gemspec'
  end

  desc 'Clean the gem files'
  task :clean do
    sh 'rm -f *.gem'
  end

  desc 'Push the gem to RubyGems'
  task :push do
    gem_file = "deadfinder-#{DeadFinder::VERSION}.gem"
    sh "gem push #{gem_file}"
  end
end
