# frozen_string_literal: true

require "rails_helper"

RSpec.describe "the store domain" do
  def place_order(number)
    OrderSeeds.place_order(number: number, customer: "Spec Customer",
                           items: { "Reading lamp" => 2, "Ceramic vase" => 1 })
  end

  describe "totals" do
    it "sums quantity times the fixed unit price" do
      order = place_order("SPEC-TOTAL")
      lamp = Product.find_by!(name: "Reading lamp")
      vase = Product.find_by!(name: "Ceramic vase")

      expect(order.total_cents).to eq(2 * lamp.price_cents + vase.price_cents)
    end

    it "fixes the unit price at order time: a catalog change never rewrites history" do
      order = place_order("SPEC-PRICE-PIN")
      before_change = order.total_cents

      Product.find_by!(name: "Reading lamp").update!(price_cents: 99_999)

      expect(order.reload.total_cents).to eq(before_change)
    end
  end

  describe "refundable? across shipment states" do
    it "refunds while there is no shipment or it has not sailed, refuses after" do
      order = OrderSeeds.pay_order(place_order("SPEC-REFUND-MATRIX"))
      expect(order.can_fire?(:refund)).to be(true)

      shipment = Shipment.create!(number: "SHIP-SPEC-MATRIX", order: order)
      expect(order.reload.can_fire?(:refund)).to be(true)

      shipment.pack!(metadata: {})
      expect(order.reload.can_fire?(:refund)).to be(true)

      shipment.ship!(metadata: {})
      expect(order.reload.can_fire?(:refund)).to be(false)

      shipment.deliver!(metadata: {})
      expect(order.reload.can_fire?(:refund)).to be(false)
    end
  end

  describe "associations" do
    it "requires an order on every payment" do
      expect { Payment.create!(number: "SPEC-ORPHAN", amount_cents: 1) }
        .to raise_error(ActiveRecord::RecordInvalid)
    end

    it "reads express from the order, not the shipment" do
      order = OrderSeeds.pay_order(
        OrderSeeds.place_order(number: "SPEC-EXPRESS", customer: "Spec",
                               items: { "Wool rug" => 1 }, express: true)
      )
      shipment = Shipment.create!(number: "SHIP-SPEC-EXPRESS", order: order)
      expect(shipment.express?).to be(true)
    end
  end
end
