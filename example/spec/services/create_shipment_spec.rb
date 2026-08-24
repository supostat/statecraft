# frozen_string_literal: true

require "rails_helper"

RSpec.describe CreateShipment do
  def paid_order(number)
    OrderSeeds.pay_order(
      OrderSeeds.place_order(number: number, customer: "Service Sue",
                             items: { "Ceramic vase" => 1 })
    )
  end

  it "creates the shipment for a paid order under the store's number convention" do
    order = paid_order("SPEC-CS-1")

    shipment = described_class.call(order: order)

    expect(shipment).to be_persisted
    expect(shipment.number).to eq("SHIP-SPEC-CS-1")
    expect(shipment.order).to eq(order)
    expect(shipment[:state]).to eq("pending")
  end

  it "holds the domain invariant: paid only, one shipment per order" do
    unpaid = OrderSeeds.place_order(number: "SPEC-CS-2", customer: "Service Sue",
                                    items: { "Ceramic vase" => 1 })
    expect { described_class.call(order: unpaid) }
      .to raise_error(ArgumentError, /needs a paid order/)

    order = paid_order("SPEC-CS-3")
    described_class.call(order: order)
    expect { described_class.call(order: order.reload) }
      .to raise_error(ArgumentError, /already has a shipment/)
  end
end
