# frozen_string_literal: true

module Statecraft
  # Publishes the two ActiveSupport::Notifications events of the pipeline.
  # Success and refusal need different event names, so timing is measured
  # manually and published with explicit start/finish instead of a naive
  # instrument block. Metadata never enters a payload: subscribers routinely
  # log payloads whole, and metadata is the one place PII can live — whoever
  # needs it reads the log record. Refusal events are published after the
  # savepoint rollback, outside the transaction, so a subscriber writing to
  # the database is never rolled back together with the pipeline.
  module Instrumentation
    TRANSITION_EVENT = "transition.statecraft"
    FAILURE_EVENT = "transition_failed.statecraft"

    def self.publish_transition(started_at:, record:, machine_class:, log_record:)
      publish(
        TRANSITION_EVENT, started_at,
        record_class: record.class.base_class.name,
        record_id: record.id,
        machine: machine_class.name,
        from: log_record.from_state.to_sym,
        to: log_record.to_state.to_sym,
        event: log_record.event&.to_sym
      )
    end

    def self.publish_failure(started_at:, record:, machine_class:, reason:, details:)
      publish(
        FAILURE_EVENT, started_at,
        {
          record_class: record.class.base_class.name,
          record_id: record.id,
          machine: machine_class.name,
          reason: reason
        }.merge(details)
      )
    end

    def self.publish(event_name, started_at, payload)
      ActiveSupport::Notifications.publish(
        event_name, started_at, Time.current, "statecraft", payload
      )
    end
    private_class_method :publish
  end
end
