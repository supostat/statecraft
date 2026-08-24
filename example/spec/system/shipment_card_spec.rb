# frozen_string_literal: true

require "rails_helper"

# catalog: 32-conditional-cascade
# catalog: 33-feed-inversion

RSpec.describe "the shipment card", type: :system do
  it "express: one pack click cascades to shipped — two history rows on one re-render" do
    shipment = Shipment.create!(number: "SPEC-SHIP-EXPRESS", express: true)
    visit shipment_path(shipment)

    click_button "pack"

    expect(page).to have_text("pack fired: the shipment is now shipped")
    expect(page).to have_css("code", text: "shipped")
    expect(page).to have_css(".history td", text: "pack")
    expect(page).to have_css(".history td", text: "ship")
  end

  it "the feed keeps the cascade's pair inverted: the nested link lands first" do
    shipment = Shipment.create!(number: "SPEC-SHIP-FEED", express: true)
    shipment.pack!(metadata: {})

    visit operations_path

    rows = page.all("table.operations tbody tr").map(&:text).select { |text| text.include?("##{shipment.id}") && text.include?("Shipment") }
    expect(rows.length).to eq(2)
    expect(rows.first).to include("ship")
    expect(rows.last).to include("pack")
  end

  it "regular: packs and honestly waits — the chain does not fire where none is declared" do
    shipment = Shipment.find_by!(number: "SHIP-REGULAR")
    expect(shipment[:state]).to eq("packed")

    visit shipment_path(shipment)

    expect(page).to have_css("code", text: "packed")
    expect(page).to have_button("ship")
    expect(page).to have_no_button("deliver")
  end
end
