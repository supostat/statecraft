# frozen_string_literal: true

class Shipment < ApplicationRecord
  state_machine ShipmentFlow, helpers: true, scopes: true

  belongs_to :order

  # Express is the order's promise; the shipment only carries it out.
  def express?
    order.express?
  end
end
