# frozen_string_literal: true

module Statecraft
  module RSpec
    # expect(OrderFlow).to have_edge(:pending, :cancelled).via(:cancel)
    #
    # The class-level shape question of transitions_from: no guards are
    # consulted, exactly like the method itself. via asserts that the
    # named events ride the edge; a bare edge simply has none.
    class HaveEdge
      def initialize(from_state, to_state)
        @from_state = from_state.to_sym
        @to_state = to_state.to_sym
        @expected_events = []
      end

      def via(*event_names)
        @expected_events = event_names.map(&:to_sym)
        self
      end

      def matches?(machine_class)
        @machine_class = machine_class
        @edge = machine_class.transitions_from(@from_state)
                             .find { |descriptor| descriptor[:to] == @to_state }
        @edge && (@expected_events - @edge[:events]).empty?
      end

      def failure_message
        unless @edge
          return ["expected #{@machine_class.name} to declare an edge #{@from_state.inspect} -> #{@to_state.inspect}",
                  StateReport.declared_shape(@machine_class, @from_state)].join("\n  ")
        end

        missing = (@expected_events - @edge[:events]).map(&:inspect).join(", ")
        "expected the edge #{@from_state.inspect} -> #{@to_state.inspect} to carry #{missing}, " \
          "but its events are #{@edge[:events].inspect}"
      end

      def failure_message_when_negated
        "expected #{@machine_class.name} not to declare the edge #{@from_state.inspect} -> #{@to_state.inspect}, " \
          "but it does (events: #{@edge[:events].inspect})"
      end

      def description
        "have an edge #{@from_state.inspect} -> #{@to_state.inspect}"
      end
    end
  end
end
