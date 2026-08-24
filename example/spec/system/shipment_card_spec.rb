# frozen_string_literal: true

require "rails_helper"

# catalog: 32-conditional-cascade
# catalog: 33-feed-inversion

RSpec.describe "the shipment card", type: :system do
  def paid_order(number, express: false)
    OrderSeeds.pay_order(
      OrderSeeds.place_order(number: number, customer: "Spec Operator",
                             items: { "Reading lamp" => 1 }, express: express)
    )
  end

  it "express: one pack click cascades to shipped — two history rows on one re-render" do
    shipment = Shipment.create!(number: "SHIP-SPEC-EXPRESS", order: paid_order("SPEC-EXP", express: true))
    visit shipment_path(shipment)

    click_button "pack"

    expect(page).to have_text("pack fired: the shipment is now shipped")
    expect(page).to have_css("code", text: "shipped")
    expect(page).to have_css(".history td", text: "pack")
    expect(page).to have_css(".history td", text: "ship")
  end

  it "the feed keeps the cascade's pair inverted: the nested link lands first" do
    shipment = Shipment.create!(number: "SHIP-SPEC-FEED", order: paid_order("SPEC-FEED", express: true))
    shipment.pack!(metadata: {})

    visit operations_path

    rows = page.all("table.operations tbody tr").map(&:text)
               .select { |text| text.include?("Shipment ##{shipment.id}") }
    expect(rows.length).to eq(2)
    expect(rows.first).to include("ship")
    expect(rows.last).to include("pack")
  end

  it "regular: packs and honestly waits — the chain does not fire where none is declared" do
    shipment = Order.find_by!(number: "ORD-1010").shipment
    expect(shipment[:state]).to eq("packed")

    visit shipment_path(shipment)

    expect(page).to have_css("code", text: "packed")
    expect(page).to have_button("ship")
    expect(page).to have_no_button("deliver")
  end
end
