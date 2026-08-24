# frozen_string_literal: true

require "rails_helper"

# catalog: 33-feed-inversion
# catalog: 38-full-journey

# The wire: one walk down the main path over the REAL modules of both zones —
# no mocks anywhere, the app has no network boundary. The customer shops and
# pays in human words; the operator confirms, ships and delivers with the
# gem's mechanics on screen; the feed keeps the whole story, refusal included.
RSpec.describe "the full journey", type: :system do
  before { sign_in_as("Ada Admin (admin)") }

  it "walks customer checkout -> operator confirmation -> cascade -> delivered -> the feed" do
    # The customer: catalog -> cart -> express checkout -> Pay.
    visit "/"
    expect(page).to have_current_path(products_path)
    within("tr", text: "Walnut desk") { click_button "Add to cart" }
    visit cart_path
    expect(page).to have_text("Total: $799.00")
    click_link "Proceed to checkout"
    fill_in "customer_name", with: "Journey Jane"
    check "express"
    click_button "Place the order"
    expect(page).to have_text("Awaiting payment")
    expect(page).to have_text("express delivery")

    click_button "Pay"
    expect(page).to have_text("Payment pending confirmation")

    order = Order.find_by!(customer_name: "Journey Jane")
    payment = order.payment

    # The operator: confirming the payment captures it and pays the order.
    visit admin_payment_path(payment)
    click_button "capture"
    expect(page).to have_text("capture fired: the payment is captured and the order is paid.")

    # The customer sees the human word for it.
    visit my_order_path(order)
    expect(page).to have_text("Paid")

    # The operator ships: creation from the paid card, the express cascade,
    # the manual deliver.
    visit admin_order_path(order)
    click_button "Create shipment"
    expect(page).to have_text("Shipment created.")
    click_button "pack"
    expect(page).to have_text("pack fired: the shipment is now shipped")
    click_button "deliver"
    expect(page).to have_text("deliver fired: the shipment is now delivered")

    visit my_order_path(order)
    expect(page).to have_text("Delivered")

    # A second, credit checkout whose reasonless cancellation lands in the
    # feed as a refusal — told to the customer in storefront words.
    visit products_path
    within("tr", text: "Ceramic vase") { click_button "Add to cart" }
    visit checkout_path
    fill_in "customer_name", with: "Journey Jane"
    check "credit"
    click_button "Place the order"
    expect(page).to have_text("paid on credit")
    credit_order = Order.order(:id).last
    click_button "Cancel the order"
    expect(page).to have_text("We couldn't cancel this order")
    expect(page).to have_no_text("GuardFailed")

    # The feed keeps the whole story: the confirmation, the inverted cascade
    # pair, the delivery and the refusal with its reason.
    shipment = order.shipment
    visit admin_operations_path
    expect(page).to have_text("Payment ##{payment.id}")
    expect(page).to have_css("tr", text: "deliver")
    expect(page).to have_css(".refused", text: "refused: guard_failed")
    expect(page).to have_text("Order ##{credit_order.id}")
    shipment_rows = page.all("table.operations tbody tr").map(&:text)
                        .select { |text| text.include?("Shipment ##{shipment.id}") }
    expect(shipment_rows.length).to eq(3)
    expect(shipment_rows[0]).to include("ship")
    expect(shipment_rows[1]).to include("pack")
    expect(shipment_rows[2]).to include("deliver")
  end
end
