# frozen_string_literal: true

module Statecraft
  module RSpec
    # The example-facing surface: requiring statecraft/rspec includes this
    # module into every example group, so specs call the factories bare.
    # Record-level matchers consult guards (a prediction with the metadata
    # you pass); class-level matchers answer the graph's shape only.
    # rubocop:disable Naming/PredicatePrefix -- have_* is RSpec's matcher idiom, not a predicate
    module Matchers
      def allow_event(event_name)
        AllowEvent.new(event_name)
      end

      def refuse_event(event_name)
        RefuseEvent.new(event_name)
      end

      def allow_transition_to(target_state)
        AllowTransitionTo.new(target_state)
      end

      def have_transitioned_to(state_name)
        HaveTransitionedTo.new(state_name)
      end

      def have_edge(from_state, to_state)
        HaveEdge.new(from_state, to_state)
      end

      def have_initial_state(state_name)
        HaveInitialState.new(state_name)
      end

      def transition(record)
        Transition.new(record)
      end
    end
    # rubocop:enable Naming/PredicatePrefix
  end
end
