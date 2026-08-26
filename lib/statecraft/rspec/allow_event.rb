# frozen_string_literal: true

module Statecraft
  module RSpec
    # expect(record).to allow_event(:pay).with_metadata("amount" => 5)
    #
    # The can_fire? question, asked with the same metadata the production
    # call will carry. The failure message walks the layers the pipeline
    # walks: is the event declared from this state, and if so, which
    # guards said no.
    class AllowEvent
      def initialize(event_name)
        @event_name = event_name.to_sym
        @metadata = {}
      end

      def with_metadata(metadata)
        @metadata = metadata
        self
      end

      def matches?(record)
        @record = record
        record.can_fire?(@event_name, metadata: @metadata)
      end

      def failure_message
        lines = ["expected #{StateReport.standing(@record)} to allow event #{@event_name.inspect}, but it was refused"]
        if StateReport.event_declared?(@record, @event_name)
          lines << StateReport.refusal(@record, @event_name, @metadata)
        else
          lines << "event #{@event_name.inspect} is not declared from #{StateReport.current_state(@record).inspect}"
          lines << StateReport.declared_shape_of(@record)
        end
        lines.join("\n  ")
      end

      def failure_message_when_negated
        "expected #{StateReport.standing(@record)} not to allow event #{@event_name.inspect}, " \
          "but the guards passed with metadata #{@metadata.inspect}"
      end

      def description
        "allow event #{@event_name.inspect}"
      end
    end
  end
end
