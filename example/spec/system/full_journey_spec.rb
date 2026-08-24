# frozen_string_literal: true

require "rails_helper"

# catalog: 33-feed-inversion
# catalog: 38-full-journey

# The wire: one walk down the main path over the REAL modules of every
# chapter — no mocks anywhere, the app has no network boundary. The journey
# builds its own records through the seed helpers and ends where the
# operator ends: at the feed, refusal included.
RSpec.describe "the full journey", type: :system do
  it "walks seed -> pay -> refusal -> capture -> cascade -> the operations log" do
    visit "/"
    expect(page).to have_current_path(products_path)
    expect(page).to have_text("Walnut desk")

    order = OrderSeeds.place_order(number: "JRN-ORD", customer: "Journey Jane",
                                   items: { "Reading lamp" => 1 })
    visit order_path(order)
    expect(page).to have_text("created in pending — the log is silent about birth")
    click_button "pay"
    expect(page).to have_text("pay fired: the order is now paid")
    expect(page).to have_css(".history td", text: "pay")

    refused = OrderSeeds.place_order(number: "JRN-ORD-REFUSED", customer: "Journey Jane",
                                     items: { "Ceramic vase" => 1 })
    visit order_path(refused)
    click_button "cancel"
    expect(page).to have_text("Refused:")
    expect(page).to have_css("code", text: "pending")

    paying = OrderSeeds.request_payment(
      OrderSeeds.place_order(number: "JRN-PAY", customer: "Journey Jane",
                             items: { "Wool rug" => 1 })
    )
    payment = paying.payment
    visit payment_path(payment)
    click_button "capture"
    expect(page).to have_text("capture fired: the payment is now captured")

    shipped_order = OrderSeeds.pay_order(
      OrderSeeds.place_order(number: "JRN-SHIP", customer: "Journey Jane",
                             items: { "Walnut desk" => 1 }, express: true)
    )
    shipment = Shipment.create!(number: "SHIP-JRN", order: shipped_order)
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
