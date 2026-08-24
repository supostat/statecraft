# frozen_string_literal: true

# Shared home for private guard helpers used by several machines. Keep it
# free of DSL declarations (states, transitions, events): machine definitions
# are NOT inherited — each machine declares its own graph.
class ApplicationMachine
  include Statecraft::Machine
end
