# frozen_string_literal: true

require "rails_helper"

RSpec.describe PlaceOrder do
  let(:uma) { User.find_by!(role: "user") }
  let(:lamp) { Product.find_by!(name: "Reading lamp") }
  let(:rug) { Product.find_by!(name: "Wool rug") }

  it "births the order with its items in one transaction, prices fixed now" do
    order = described_class.call(
      user: uma,
      cart: { lamp.id.to_s => 2, rug.id.to_s => 1 },
      customer_name: "Service Sue"
    )

    expect(order).to be_persisted
    expect(order.user).to eq(uma)
    expect(order[:state]).to eq("pending")
    expect(order.items.count).to eq(2)
    expect(order.total_cents).to eq(2 * lamp.price_cents + rug.price_cents)
  end

  it "births a CreditOrder when asked, express riding along" do
    order = described_class.call(
      user: uma, cart: { lamp.id.to_s => 1 },
      customer_name: "Service Sue", express: true, credit: true
    )

    expect(order).to be_a(CreditOrder)
    expect(order.express?).to be(true)
  end

  it "refuses an empty cart before touching the database" do
    expect do
      described_class.call(user: uma, cart: {}, customer_name: "Nobody")
    end.to raise_error(ArgumentError, /cart is empty/)
  end
end
