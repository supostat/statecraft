# frozen_string_literal: true

# Thin orchestrator: each chapter owns a scenario library under db/seeds/
# with named helpers that seed through the honest pipeline (pay!, cancel!,
# ...) — create! is reserved for birth in the initial state. db:seed in the
# test environment IS the e2e fixture set: one source of truth.
Dir[File.expand_path("seeds/*.rb", __dir__)].each { |scenario| load scenario }
