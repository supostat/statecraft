# frozen_string_literal: true

# Regular: packs and honestly waits in packed — the chain does not fire
# where it is not declared.
OrderSeeds.place_order(number: "ORD-1010", customer: "Jack Turner",
                       items: { "Oak bookshelf" => 1 }).then do |order|
  OrderSeeds.pay_order(order)
  shipment = Shipment.create!(number: "SHIP-#{order.number}", order: order)
  shipment.pack!(metadata: { "note" => "seeded packing" })
end

# Express: one pack! and the cascade sails it to shipped — two log rows from
# one call, the feed keeps the inverted pair.
OrderSeeds.place_order(number: "ORD-1011", customer: "Kira Novak",
                       items: { "Walnut desk" => 1 }, express: true).then do |order|
  OrderSeeds.pay_order(order)
  shipment = Shipment.create!(number: "SHIP-#{order.number}", order: order)
  shipment.pack!(metadata: { "note" => "seeded express" })
end
