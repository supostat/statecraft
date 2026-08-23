# frozen_string_literal: true

module Statecraft
  class Pipeline
    # The record-facing API mixed into the model at mounting time. Bang
    # variants return the created log record; non-bang variants return it too,
    # or false on GuardFailed / InvalidTransition. Programmer errors and
    # TransitionConflict always raise.
    module Surface
      def transition_to!(to_state, metadata: {}, bypass_events: false)
        Pipeline.new(self).direct(to_state, metadata: metadata, bypass_events: bypass_events)
      end

      def transition_to(to_state, metadata: {}, bypass_events: false)
        transition_to!(to_state, metadata: metadata, bypass_events: bypass_events)
      rescue GuardFailed, InvalidTransition
        false
      end

      def fire!(event_name, metadata: {})
        Pipeline.new(self).fire(event_name, metadata: metadata)
      end

      def fire(event_name, metadata: {})
        fire!(event_name, metadata: metadata)
      rescue GuardFailed, InvalidTransition
        false
      end
    end
  end
end
