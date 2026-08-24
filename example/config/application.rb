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

    # The card is ONE metadata form whose buttons aim different transition
    # actions via formaction (plain HTML, zero JS). Per-form CSRF tokens are
    # scoped to the form's own action and would refuse every such click, so
    # the app uses the session-wide token; forgery protection itself stays on.
    config.action_controller.per_form_csrf_tokens = false
  end
end
