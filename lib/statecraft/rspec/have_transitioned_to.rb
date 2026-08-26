# frozen_string_literal: true

module Statecraft
  module RSpec
    # expect(record).to have_transitioned_to(:paid)
    #
    # Strictly log-based, like transitioned_to? itself: the question is
    # about history, never about the current state. The failure message
    # shows what the log actually holds.
    class HaveTransitionedTo
      def initialize(state_name)
        @state_name = state_name.to_sym
      end

      def matches?(record)
        @record = record
        record.transitioned_to?(@state_name)
      end

      def failure_message
        "expected the log of #{StateReport.standing(@record)} to hold a transition to #{@state_name.inspect}, " \
          "but #{log_contents}"
      end

      def failure_message_when_negated
        "expected the log of #{StateReport.standing(@record)} to hold no transition to #{@state_name.inspect}, " \
          "but it does"
      end

      def description
        "have transitioned to #{@state_name.inspect}"
      end

      private

      def log_contents
        to_states = @record.history.map(&:to_state)
        return "the log is empty" if to_states.empty?

        "the log holds transitions to: #{to_states.join(", ")}"
      end
    end
  end
end
