# frozen_string_literal: true

module Statecraft
  module RSpec
    # expect { order.fire!(:pay) }.to transition(order)
    #   .from(:pending).to(:paid).via_event(:pay).with_metadata("k" => "v")
    #
    # The transition through the eyes of a test: the state column moved to
    # the target AND exactly one log row was appended with the matching
    # from/to/event/metadata. A non-bang call that returned false leaves
    # both untouched — the matcher fails and explains why, from the same
    # introspection the pipeline consulted. Exceptions of the bang forms
    # fly through, like with the change matcher: refusals are asserted
    # with refuse_event or raise_error, not here.
    class Transition
      def initialize(record)
        @record = record
        @failures = []
      end

      def from(state_name)
        @from_state = state_name.to_sym
        self
      end

      def to(state_name)
        @to_state = state_name.to_sym
        self
      end

      def via_event(event_name)
        @event_name = event_name.to_sym
        self
      end

      def with_metadata(metadata)
        @metadata = metadata
        self
      end

      def supports_block_expectations?
        true
      end

      def matches?(block)
        raise ArgumentError, "transition(record).to(:state) — the .to target is required" unless @to_state

        @before_state = StateReport.current_state(@record)
        appended_before = @record.history.count
        block.call
        @after_state = StateReport.current_state(@record)
        @appended = @record.history.offset(appended_before).to_a
        collect_failures
        @failures.empty?
      end

      def failure_message
        expected_event = " via event #{@event_name.inspect}" if @event_name
        header = "expected the block to transition #{@record.class.name} " \
                 "#{@before_state.inspect} -> #{@to_state.inspect}#{expected_event}"
        ([header] + @failures).join("\n  ")
      end

      def failure_message_when_negated
        row = @appended.last
        written_by = " by event #{row.event.inspect}" if row.event
        "expected the block not to transition #{@record.class.name} to #{@to_state.inspect}, " \
          "but it did: #{row.from_state.inspect} -> #{row.to_state.inspect}#{written_by}"
      end

      def description
        "transition #{@record.class.name} to #{@to_state.inspect}"
      end

      private

      def collect_failures
        return collect_missing_transition if @appended.empty?

        if @appended.size > 1
          @failures << "expected exactly one appended log row, but the block appended #{@appended.size}"
        end
        if @after_state != @to_state
          @failures << "the record ended in #{@after_state.inspect}, not #{@to_state.inspect}"
        end
        collect_row_mismatches(@appended.last)
      end

      def collect_row_mismatches(row)
        if row.to_state != @to_state.to_s
          @failures << "the log row went to #{row.to_state.inspect}, not #{@to_state.inspect}"
        end
        if @from_state && row.from_state != @from_state.to_s
          @failures << "the transition started from #{row.from_state.inspect}, not #{@from_state.inspect}"
        end
        if @event_name && row.event != @event_name.to_s
          @failures << "the transition was written by event #{row.event.inspect}, not #{@event_name.inspect}"
        end
        collect_metadata_mismatch(row)
      end

      def collect_missing_transition
        @failures << "no transition happened: the record stayed in #{@after_state.inspect}"
        @failures << StateReport.reachable(@record, @metadata || {})
        return unless @event_name && StateReport.event_declared?(@record, @event_name)

        @failures << StateReport.refusal(@record, @event_name, @metadata || {})
      end

      def collect_metadata_mismatch(row)
        return unless @metadata

        expected = @metadata.deep_stringify_keys
        return if row.metadata == expected

        @failures << "the log row carries metadata #{row.metadata.inspect}, not #{expected.inspect}"
      end
    end
  end
end
