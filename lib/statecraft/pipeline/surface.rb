# frozen_string_literal: true

module Statecraft
  class Pipeline
    # The record-facing API mixed into the model at mounting time. Bang
    # variants return the created log record; non-bang variants return it too,
    # or false on GuardFailed / InvalidTransition. Programmer errors and
    # TransitionConflict — StaleTransition included — always raise.
    module Surface
      def transition_to!(to_state, metadata: {}, bypass_events: false, seen: nil)
        Pipeline.new(self).direct(to_state, metadata: metadata, bypass_events: bypass_events, seen: seen)
      end

      def transition_to(to_state, metadata: {}, bypass_events: false, seen: nil)
        transition_to!(to_state, metadata: metadata, bypass_events: bypass_events, seen: seen)
      rescue GuardFailed, InvalidTransition
        false
      end

      def fire!(event_name, metadata: {}, seen: nil)
        Pipeline.new(self).fire(event_name, metadata: metadata, seen: seen)
      end

      def fire(event_name, metadata: {}, seen: nil)
        fire!(event_name, metadata: metadata, seen: seen)
      rescue GuardFailed, InvalidTransition
        false
      end
    end
  end
end
