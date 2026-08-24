# frozen_string_literal: true

# readme: machine-skeleton
class OrderFlow
  include Statecraft::Machine

  state :pending, initial: true
  state :paid
  state :refunded
  state :cancelled

  event :pay, from: :pending, to: :paid
  event :refund, from: :paid, to: :refunded, guard: :refundable?

  # One edge, the whole event layer: a guarded event, an unguarded privileged
  # event and the bypass path all share pending -> cancelled — the log
  # records HOW, not only WHAT.
  event :cancel, from: :pending, to: :cancelled, guard: :cancellable?
  event :admin_override, from: :pending, to: :cancelled

  private

  # Refundability is a property of the record, not of the metadata: money
  # comes back only while the shipment has not sailed. The TOCTOU scene
  # lives exactly in this gap.
  def refundable?(record, _metadata)
    shipment = record.shipment
    shipment.nil? || %w[pending packed].include?(shipment[:state])
  end

  # Credit orders cancel only through the admin paths — the same click
  # refuses differently for the two STI types on one screen.
  def cancellable?(record, metadata)
    return false if record.is_a?(CreditOrder)

    metadata["reason"].to_s.strip.present?
  end
end
# /readme
