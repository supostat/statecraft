# frozen_string_literal: true

require "statecraft"

# Deliberately not required by lib/statecraft.rb: the matchers exist only
# where RSpec does, and the gem's runtime must not know about test
# frameworks. This file is the one opt-in door.
unless defined?(RSpec)
  raise Statecraft::Error,
        "statecraft/rspec builds RSpec matchers, so RSpec must be loaded first: " \
        "require statecraft/rspec from your spec helper, after rspec itself"
end

require_relative "rspec/state_report"
require_relative "rspec/allow_event"
require_relative "rspec/refuse_event"
require_relative "rspec/allow_transition_to"
require_relative "rspec/have_transitioned_to"
require_relative "rspec/have_edge"
require_relative "rspec/have_initial_state"
require_relative "rspec/transition"
require_relative "rspec/matchers"

RSpec.configure { |config| config.include Statecraft::RSpec::Matchers }
