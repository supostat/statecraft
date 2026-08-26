# frozen_string_literal: true

module Statecraft
  module RSpec
    # expect(OrderFlow).to have_initial_state(:pending)
    class HaveInitialState
      def initialize(state_name)
        @state_name = state_name.to_sym
      end

      def matches?(machine_class)
        @machine_class = machine_class
        machine_class.initial_state == @state_name
      end

      def failure_message
        "expected the initial state of #{@machine_class.name} to be #{@state_name.inspect}, " \
          "but it is #{@machine_class.initial_state.inspect}"
      end

      def failure_message_when_negated
        "expected the initial state of #{@machine_class.name} not to be #{@state_name.inspect}, but it is"
      end

      def description
        "have the initial state #{@state_name.inspect}"
      end
    end
  end
end
