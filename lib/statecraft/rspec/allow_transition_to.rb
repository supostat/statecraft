# frozen_string_literal: true

module Statecraft
  module RSpec
    # expect(record).to allow_transition_to(:paid).via(:pay)
    # expect(record).to allow_transition_to(:archived).directly
    #
    # The available_transitions prediction for one target: not only
    # whether the record can go there, but HOW — via lists the events
    # whose guards pass, directly asserts the guard-free direct way.
    class AllowTransitionTo
      def initialize(target_state)
        @target_state = target_state.to_sym
        @expected_via = []
        @directly = false
        @metadata = {}
      end

      def via(*event_names)
        @expected_via = event_names.map(&:to_sym)
        self
      end

      def directly
        @directly = true
        self
      end

      def with_metadata(metadata)
        @metadata = metadata
        self
      end

      def matches?(record)
        @record = record
        @availability = record.available_transitions(metadata: @metadata)
                              .find { |availability| availability.to == @target_state }
        return false unless @availability

        missing_ways.empty?
      end

      def failure_message
        unless @availability
          return ["expected #{StateReport.standing(@record)} to reach #{@target_state.inspect}, but it cannot",
                  StateReport.reachable(@record, @metadata),
                  StateReport.declared_shape_of(@record)].join("\n  ")
        end

        "expected the way to #{@target_state.inspect} to include #{missing_ways.map(&:inspect).join(", ")}, " \
          "but it is reachable via #{@availability.via.inspect}"
      end

      def failure_message_when_negated
        "expected #{StateReport.standing(@record)} not to reach #{@target_state.inspect}, " \
          "but it is reachable via #{@availability.via.inspect}"
      end

      def description
        "allow a transition to #{@target_state.inspect}"
      end

      private

      def missing_ways
        expected = @expected_via + (@directly ? [:direct] : [])
        expected - @availability.via
      end
    end
  end
end
