# frozen_string_literal: true

source "https://rubygems.org"

gemspec

gem "irb"
gem "rake", "~> 13.0"

gem "minitest", "~> 6"
gem "mocha", "~> 3.0"
gem "simplecov", "~> 0.22", require: false

gem "standard"
gem "standard-performance"
gem "rubocop-minitest"
gem "rubocop-rake"

gem "yard", "~> 0.9"
gem "redcarpet", "~> 3.6"

# Interop tests reference verquest request classes.
gem "verquest", "~> 0.7.1"

group :bench do
  gem "benchmark-ips", "~> 2.14", require: false
  gem "alba", require: false
  gem "blueprinter", require: false
end
