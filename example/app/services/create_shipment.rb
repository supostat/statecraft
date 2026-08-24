# frozen_string_literal: true

# A shipment needs a paid order without one — the domain invariant lives
# here, not in the controller; the number follows the store's convention.
class CreateShipment
  def self.call(order:)
    raise ArgumentError, "a shipment needs a paid order" unless order[:state] == "paid"
    raise ArgumentError, "the order already has a shipment" if order.shipment.present?

    Shipment.create!(number: "SHIP-#{order.number}", order: order)
  end
end
