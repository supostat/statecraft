# frozen_string_literal: true

source "https://rubygems.org"

gemspec

if ENV["AR_VERSION"]
  gem "activerecord", "~> #{ENV["AR_VERSION"]}.0"
  gem "activesupport", "~> #{ENV["AR_VERSION"]}.0"
end

group :development do
  gem "pg", ">= 1.5"
  gem "rspec", "~> 3.13"
  gem "sqlite3", ">= 2.1"

  # Generator tests only (Rails::Generators::TestCase); runtime independence from
  # railties is enforced by spec/statecraft/gem_hygiene_spec.rb.
  gem "rails", ENV["AR_VERSION"] ? "~> #{ENV["AR_VERSION"]}.0" : ">= 7.2"
end
