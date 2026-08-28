# frozen_string_literal: true

# readme: machine-skeleton
class OrderFlow
  include Statecraft::Machine

  state :pending, initial: true
  state :paid
  state :refunded
  state :cancelled

  event :pay, from: :pending, to: :paid
  event :refund, from: :paid, to: :refunded, record_guard: :refundable?

  # One edge, the whole event layer: a guarded event, an unguarded privileged
  # event and the bypass path all share pending -> cancelled — the log
  # records HOW, not only WHAT. The cancel guards split by nature: the
  # record layer judges the order (and the offering may ask it), the input
  # layer judges what the operator typed — and is marked input_guard:, so a
  # question asked without metadata raises instead of predicting a false no.
  event :cancel, from: :pending, to: :cancelled,
        record_guard: :customer_cancellable?, input_guard: :reason_present?
  event :admin_override, from: :pending, to: :cancelled

  private

  # The machine keeps the registry "event -> predicate" and delegates the
  # domain facts to the record.
  def refundable?(record) = record.refundable?

  def customer_cancellable?(record) = record.customer_cancellable?

  def reason_present?(_record, metadata)
    metadata["reason"].to_s.strip.present?
  end
end
# /readme
