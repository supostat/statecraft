# frozen_string_literal: true

module Statecraft
  module RSpec
    # expect(record).to refuse_event(:cancel).because_of(:customer_cancellable?)
    #
    # The named negation of allow_event: the refusal itself, and — through
    # because_of — WHO refused. Guard names come from refusals_for, so
    # because_of sees record-layer guards only; an input-reading guard:
    # has no name there, and the failure message says so instead of
    # pretending otherwise.
    class RefuseEvent
      def initialize(event_name)
        @event_name = event_name.to_sym
        @expected_guards = []
        @metadata = {}
      end

      def because_of(*guard_names)
        @expected_guards = guard_names.map(&:to_sym)
        self
      end

      def with_metadata(metadata)
        @metadata = metadata
        self
      end

      def matches?(record)
        @record = record
        @allowed = record.can_fire?(@event_name, metadata: @metadata)
        return false if @allowed

        @refusing_guards = record.refusals_for(@event_name).map(&:guard)
        (@expected_guards - @refusing_guards).empty?
      end

      def failure_message
        if @allowed
          return "expected #{StateReport.standing(@record)} to refuse event #{@event_name.inspect}, " \
                 "but the guards passed with metadata #{@metadata.inspect}"
        end

        missing = (@expected_guards - @refusing_guards).map(&:inspect).join(", ")
        "expected the refusal of #{@event_name.inspect} to come from #{missing}\n  #{actual_refusers}"
      end

      def failure_message_when_negated
        "expected #{StateReport.standing(@record)} to allow event #{@event_name.inspect}, but it was refused\n  " +
          StateReport.refusal(@record, @event_name, @metadata)
      end

      def description
        "refuse event #{@event_name.inspect}"
      end

      private

      def actual_refusers
        if @refusing_guards.empty?
          "but no record-layer guard refused: refusals_for names record-layer guards only, " \
            "and this refusal came from an input-reading guard: or an undeclared branch"
        else
          "but the refusing record-layer guards were: #{@refusing_guards.map(&:inspect).join(", ")}"
        end
      end
    end
  end
end
