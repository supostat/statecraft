# frozen_string_literal: true

# Thin orchestrator: each area owns a scenario library under db/seeds/
# (numeric prefixes fix the load order) with named helpers that seed through
# the honest pipeline — create! is reserved for birth in the initial state.
# db:seed in the test environment IS the e2e fixture set: one source of
# truth. Idempotency lives per file: each scenario library guards its own
# marker, so a NEW seed file still runs against an already-seeded world.
Dir[File.expand_path("seeds/*.rb", __dir__)].each { |scenario| load scenario }
