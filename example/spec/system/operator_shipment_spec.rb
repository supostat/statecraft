# frozen_string_literal: true

require "rails_helper"

# catalog: 32-conditional-cascade
# catalog: 33-feed-inversion

RSpec.describe "the operator shipment desk", type: :system do
  before { sign_in_as("Ada Admin (admin)") }

  it "creates the shipment from a paid order's card and cascades express to shipped" do
    order = OrderSeeds.pay_order(
      OrderSeeds.place_order(number: "SPEC-EXP", customer: "Spec Operator",
                             items: { "Reading lamp" => 1 }, express: true)
    )
    visit admin_order_path(order)
    click_button "Create shipment"
    expect(page).to have_text("Shipment created.")

    click_button "pack"

    expect(page).to have_text("pack fired: the shipment is now shipped")
    expect(page).to have_css(".history td", text: "pack")
    expect(page).to have_css(".history td", text: "ship")
  end

  it "the feed keeps the cascade's pair inverted: the nested link lands first" do
    order = OrderSeeds.pay_order(
      OrderSeeds.place_order(number: "SPEC-FEED", customer: "Spec Operator",
                             items: { "Wool rug" => 1 }, express: true)
    )
    shipment = Shipment.create!(number: "SHIP-SPEC-FEED", order: order)
    shipment.pack!(metadata: {})

    visit admin_operations_path

    rows = page.all("table.operations tbody tr").map(&:text)
               .select { |text| text.include?("Shipment ##{shipment.id}") }
    expect(rows.length).to eq(2)
    expect(rows.first).to include("ship")
    expect(rows.last).to include("pack")
  end

  it "regular waits in packed and deliver stays a human's click" do
    shipment = Order.find_by!(number: "ORD-1010").shipment
    expect(shipment[:state]).to eq("packed")

    visit admin_shipment_path(shipment)
    expect(page).to have_button("ship")
    expect(page).to have_no_button("deliver")

    click_button "ship"
    expect(page).to have_text("ship fired: the shipment is now shipped")

    click_button "deliver"
    expect(page).to have_text("deliver fired: the shipment is now delivered")
  end
end
