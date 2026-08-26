# frozen_string_literal: true

class Order < ApplicationRecord
  state_machine OrderFlow, versioning: true, helpers: true, scopes: true

  # Optional on purpose: orders from the pre-role era stay legal.
  belongs_to :user, optional: true

  has_many :items, class_name: "OrderItem", dependent: :destroy
  has_one :payment, dependent: :destroy
  has_one :shipment, dependent: :destroy

  def total_cents
    items.sum("quantity * unit_price_cents")
  end

  # The domain facts the machine's record guards delegate to. Money comes
  # back only while the shipment has not sailed — the TOCTOU scene lives in
  # exactly this gap.
  def refundable?
    shipment.nil? || %w[pending packed].include?(shipment[:state])
  end

  def customer_cancellable?
    true
  end
end
