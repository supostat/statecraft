# frozen_string_literal: true

module ShipmentSeeds
  module_function

  # Express: one pack! and the cascade sails it to shipped — two log rows
  # from one call, the feed keeps the inverted pair.
  def seed_express_shipment
    shipment = Shipment.create!(number: "SHIP-EXPRESS", express: true)
    shipment.pack!(metadata: { "note" => "seeded express" })
    shipment
  end

  # Regular: packs and honestly waits in packed — the proof that the chain
  # does not fire where it is not declared.
  def seed_regular_shipment
    shipment = Shipment.create!(number: "SHIP-REGULAR")
    shipment.pack!(metadata: { "note" => "seeded regular" })
    shipment
  end
end

ShipmentSeeds.seed_express_shipment
ShipmentSeeds.seed_regular_shipment
