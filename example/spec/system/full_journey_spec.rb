# frozen_string_literal: true

require "rails_helper"

# catalog: 33-feed-inversion
# catalog: 38-full-journey

# The wire: one walk down the main path over the REAL modules of every
# chapter — no mocks anywhere, the app has no network boundary. The journey
# creates its own records (birth in the initial state is the sanctioned
# create!) and ends where the operator ends: at the feed, refusal included.
RSpec.describe "the full journey", type: :system do
  it "walks seed -> pay -> refusal -> capture -> cascade -> the operations log" do
    visit "/"
    expect(page).to have_current_path(orders_path)
    expect(page).to have_link("ORD-FRESH")

    order = Order.create!(number: "JRN-ORD")
    visit order_path(order)
    expect(page).to have_text("created in pending — the log is silent about birth")
    click_button "pay"
    expect(page).to have_text("pay fired: the order is now paid")
    expect(page).to have_css(".history td", text: "pay")

    refused = Order.create!(number: "JRN-ORD-REFUSED")
    visit order_path(refused)
    click_button "cancel"
    expect(page).to have_text("Refused:")
    expect(page).to have_css("code", text: "pending")

    payment = Payment.create!(number: "JRN-PAY", amount_cents: 990)
    visit payment_path(payment)
    click_button "capture"
    expect(page).to have_text("capture fired: the payment is now captured")

    shipment = Shipment.create!(number: "JRN-SHIP", express: true)
    visit shipment_path(shipment)
    click_button "pack"
    expect(page).to have_text("pack fired: the shipment is now shipped")
    expect(page).to have_css(".history td", text: "pack")
    expect(page).to have_css(".history td", text: "ship")

    visit operations_path
    expect(page).to have_text("Order ##{order.id}")
    expect(page).to have_css("tr", text: "pay")
    expect(page).to have_css(".refused", text: "refused: guard_failed")
    expect(page).to have_text("Payment ##{payment.id}")
    shipment_rows = page.all("table.operations tbody tr").map(&:text)
                        .select { |text| text.include?("Shipment ##{shipment.id}") }
    expect(shipment_rows.length).to eq(2)
    expect(shipment_rows.first).to include("ship")
    expect(shipment_rows.last).to include("pack")
  end
end
