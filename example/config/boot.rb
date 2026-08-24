# frozen_string_literal: true

ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

# The production environment is absent by construction: this store exists
# to be run and read, never to be deployed.
if ENV["RAILS_ENV"] == "production" || ENV["RACK_ENV"] == "production"
  abort "the statecraft example store never runs in production: the environment does not exist"
end

require "bundler/setup"
