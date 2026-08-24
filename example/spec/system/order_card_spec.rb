# frozen_string_literal: true

require "rails_helper"

# catalog: 24-graph-gates-render
# catalog: 25-panel-contract
# catalog: 26-toctou-gap

RSpec.describe "the order card", type: :system do
  it "round-trips a click: flash, state, panel and history in the same reload" do
    order = Order.find_by!(number: "ORD-1001")
    visit order_path(order)
    expect(page).to have_text("created in pending — the log is silent about birth")

    click_button "pay"

    expect(page).to have_text("pay fired: the order is now paid")
    expect(page).to have_css("code", text: "paid")
    expect(page).to have_css(".history td", text: "pay")
  end

  it "keeps the panel honest both ways: from submitted metadata after a refusal, and via preview" do
    order = Order.create!(number: "SPEC-PANEL", customer_name: "Spec")
    visit order_path(order)

    click_button "cancel"

    expect(page).to have_text("Refused:")
    expect(page).to have_css(".available-panel", text: "cancelled")
    expect(page).to have_no_css(".available-panel li", text: "via cancel,")

    fill_in "metadata[reason]", with: "customer asked"
    click_button "preview"

    expect(page).to have_text("Preview only — nothing was written.")
    expect(page).to have_css(".available-panel li", text: "via cancel,")
    expect(page).to have_css("code", text: "pending")
  end

  it "TOCTOU: the panel's promise dies when the shipment sails between render and click" do
    order = Order.find_by!(number: "ORD-1004")
    visit order_path(order)
    expect(page).to have_css(".available-panel li", text: "refunded")

    OrderSeeds.ship_items(order)
    click_button "refund"

    expect(page).to have_text("Refused:")
    expect(page).to have_no_css(".available-panel li", text: "refunded")
  end
end
