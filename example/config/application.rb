# frozen_string_literal: true

require_relative "boot"

require "rails"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"

Bundler.require(*Rails.groups)

module StatecraftExample
  class Application < Rails::Application
    config.load_defaults 8.1

    # The harness runs only in development and test, so there is no secret to
    # keep — an inline value beats generated credentials nobody uses.
    config.secret_key_base = "statecraft-example-is-a-test-harness"
  end
end
