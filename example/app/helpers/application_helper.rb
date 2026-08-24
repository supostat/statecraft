# frozen_string_literal: true

module ApplicationHelper
  SHIPPING_STATUS = {
    "pending" => "Preparing",
    "packed" => "Packed",
    "shipped" => "On its way",
    "delivered" => "Delivered"
  }.freeze

  def shipping_status(shipment)
    SHIPPING_STATUS.fetch(shipment[:state], shipment[:state])
  end

  def price(cents)
    format("$%.2f", cents / 100.0)
  end
end
