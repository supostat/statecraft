# frozen_string_literal: true

require "rails_helper"

# catalog: 23-triple-path-edge
# catalog: 24-graph-gates-render
# catalog: 25-panel-contract
# catalog: 26-toctou-gap
# catalog: 27-sti-shared-machine

RSpec.describe "the operator order desk", type: :system do
  before { sign_in_as("Ada Admin (admin)") }

  it "lists both STI kinds and filters by the state scopes" do
    visit admin_orders_path

    expect(page).to have_link("ORD-1002")
    expect(page).to have_link("ORD-1003")
    expect(page).to have_css("td", text: "credit")

    visit admin_orders_path(state: "cancelled")
    expect(page).to have_link("ORD-1006")
    expect(page).to have_no_link("ORD-1002")

    visit admin_orders_path(state: "paid")
    expect(page).to have_link("ORD-1003")
  end

  it "hides the bypass off the cancellable edge and shows an empty filter honestly" do
    visit admin_order_path(Order.find_by!(number: "ORD-1002"))
    expect(page).to have_no_button("bypass cancel")

    refunded_ids = Order.where(state: "refunded").ids
    Payment.where(order_id: refunded_ids).delete_all
    Shipment.where(order_id: refunded_ids).delete_all
    Order.where(id: refunded_ids).delete_all

    visit admin_orders_path(state: "refunded")
    expect(page).to have_text("No orders in this state.")
  end

  it "round-trips a click with the full mechanics on screen: buttons, panel, history" do
    order = Order.find_by!(number: "ORD-1001")
    visit admin_order_path(order)
    expect(page).to have_text("created in pending — the log is silent about birth")

    click_button "pay"

    expect(page).to have_text("pay fired: the order is now paid")
    expect(page).to have_css("code", text: "paid")
    expect(page).to have_css(".history td", text: "pay")
  end

  it "keeps the panel honest both ways: from submitted metadata after a refusal, and via preview" do
    order = Order.create!(number: "SPEC-PANEL", customer_name: "Spec")
    visit admin_order_path(order)

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
    visit admin_order_path(order)
    expect(page).to have_css(".available-panel li", text: "refunded")

    OrderSeeds.ship_items(order)
    click_button "refund"

    expect(page).to have_text("Refused:")
    expect(page).to have_no_css(".available-panel li", text: "refunded")
  end

  it "the three paths of one edge stay distinguishable in the history" do
    order = Order.create!(number: "SPEC-ADMIN-BYPASS", customer_name: "Spec")
    visit admin_order_path(order)
    expect(page).to have_text("Bypass writes event: nil")

    click_button "bypass cancel"

    expect(page).to have_text("bypassed: the order is now cancelled")
    expect(page).to have_css(".history .muted", text: "direct (bypassed events)")

    other = Order.create!(number: "SPEC-ADMIN-OVERRIDE", customer_name: "Spec")
    visit admin_order_path(other)

    click_button "admin_override"

    expect(page).to have_text("admin_override fired: the order is now cancelled")
    expect(page).to have_css(".history td", text: "admin_override")
    expect(page).to have_no_css(".history .muted", text: "direct (bypassed events)")
  end
end
