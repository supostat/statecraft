# frozen_string_literal: true

# The one executable example of subscribing to statecraft's telemetry: the
# Operations log feed is written here, with create!, into an ordinary table.
# The gem publishes with explicit start/finish, so subscribers take the
# five-argument block form. Payloads never carry metadata (the gem's PII
# decision) — whoever needs it reads the transition log record instead.
ActiveSupport::Notifications.subscribe("transition.statecraft") do |_name, _started, _finished, _id, payload|
  OperationEntry.create!(
    record_class: payload[:record_class],
    record_id: payload[:record_id].to_s,
    from_state: payload[:from],
    to_state: payload[:to],
    event_name: payload[:event],
    outcome: "transition"
  )
end

ActiveSupport::Notifications.subscribe("transition_failed.statecraft") do |_name, _started, _finished, _id, payload|
  OperationEntry.create!(
    record_class: payload[:record_class],
    record_id: payload[:record_id].to_s,
    from_state: payload[:from],
    to_state: payload[:to],
    event_name: payload[:event],
    outcome: "refused",
    reason: payload[:reason].to_s
  )
end
