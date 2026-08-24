# frozen_string_literal: true

ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

# The production environment is absent by construction: this app is a test
# harness for the statecraft gem, never a deployable service.
if ENV["RAILS_ENV"] == "production" || ENV["RACK_ENV"] == "production"
  abort "the statecraft example is a test harness: the production environment does not exist"
end

require "bundler/setup"
