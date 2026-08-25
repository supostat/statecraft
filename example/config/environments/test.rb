# frozen_string_literal: true

Rails.application.configure do
  config.enable_reloading = false
  # The boot-safety spec eager loads explicitly, so the suite still proves
  # Zeitwerk without paying the price on every run.
  config.eager_load = false
  config.consider_all_requests_local = true
  config.action_dispatch.show_exceptions = :rescuable
  config.active_support.deprecation = :raise
  # The stock Rails test default: raw request-spec POSTs carry no CSRF token;
  # the system scenes still walk real forms with real tokens.
  config.action_controller.allow_forgery_protection = false
end
