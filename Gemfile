# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# An empty AR_VERSION means "not pinned": ENV values are strings, and "" is
# truthy in Ruby — a bare presence check would build the requirement "~> .0".
active_record_pin = ENV["AR_VERSION"].to_s
unless active_record_pin.empty?
  gem "activerecord", "~> #{active_record_pin}.0"
  gem "activesupport", "~> #{active_record_pin}.0"
end

group :development do
  gem "pg", ">= 1.5"
  gem "rspec", "~> 3.13"
  gem "sqlite3", ">= 2.1"

  # Generator tests only (Rails::Generators::TestCase); runtime independence from
  # railties is enforced by spec/statecraft/gem_hygiene_spec.rb.
  gem "rails", active_record_pin.empty? ? ">= 7.2" : "~> #{active_record_pin}.0"
end
