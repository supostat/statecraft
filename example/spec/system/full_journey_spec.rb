# frozen_string_literal: true

require "rails_helper"

# catalog: 33-feed-inversion
# catalog: 38-full-journey

# The wire: one walk down the main path over the REAL modules of every layer
# and all three roles — no mocks anywhere, the app has no network boundary.
# Uma shops in human words and sees only her buttons; Mark works the desks
# but holds no privileged paths; Ada bypasses; the feed keeps the whole
# story in the end.
RSpec.describe "the full journey", type: :system do
  it "walks Uma's checkout -> Mark's desks -> Ada's bypass -> the feed" do
    # Uma (the default user): catalog -> cart -> express checkout -> Pay.
    visit "/"
    expect(page).to have_current_path(products_path)
    expect(page).to have_no_link("Operations log")
    within(".product-card", text: "Walnut desk") { click_button "Add to cart" }
    visit cart_path
    expect(page).to have_text("Total: $799.00")
    click_link "Proceed to checkout"
    fill_in "customer_name", with: "Journey Jane"
    check "express"
    click_button "Place the order"
    expect(page).to have_text("Awaiting payment")
    expect(page).to have_button("Pay")
    expect(page).to have_button("Cancel the order")

    click_button "Pay"
    expect(page).to have_text("Payment pending confirmation")
    expect(page).to have_no_button("Pay")

    order = Order.find_by!(customer_name: "Journey Jane")
    payment = order.payment

    # Mark: confirming the payment captures it and pays the order; the desk
    # shows him no privileged paths, and shipping cascades for express.
    sign_in_as("Mark Manager (manager)")
    visit admin_payment_path(payment)
    click_button "capture"
    expect(page).to have_text("capture fired: the payment is captured and the order is paid.")

    visit admin_order_path(order)
    within(".transition-buttons", match: :first) do
      expect(page).to have_no_button("admin_override")
    end
    expect(page).to have_no_button("bypass cancel")
    click_button "Create shipment"
    expect(page).to have_text("Shipment created.")
    click_button "pack"
    expect(page).to have_text("pack fired: the shipment is now shipped")
    click_button "deliver"
    expect(page).to have_text("deliver fired: the shipment is now delivered")

    # Uma reads the human words for all of it.
    sign_in_as("Uma User (user)")
    visit my_order_path(order)
    expect(page).to have_text("Paid")
    expect(page).to have_text("Delivered")

    # Uma places a second, credit order; Ada bypasses it.
    visit products_path
    within(".product-card", text: "Ceramic vase") { click_button "Add to cart" }
    visit checkout_path
    fill_in "customer_name", with: "Journey Jane"
    check "credit"
    click_button "Place the order"
    expect(page).to have_text("paid on credit")
    credit_order = Order.order(:id).last

    sign_in_as("Ada Admin (admin)")
    visit admin_order_path(credit_order)
    click_button "bypass cancel"
    expect(page).to have_text("bypassed: the order is now cancelled")
    expect(page).to have_css(".history .muted", text: "direct (bypassed events)")

    sign_in_as("Uma User (user)")
    visit my_order_path(credit_order)
    expect(page).to have_text("Cancelled")

    # The feed closes the story: the confirmation, the inverted cascade
    # pair, the delivery and the bypassed row.
    sign_in_as("Ada Admin (admin)")
    shipment = order.shipment
    visit admin_operations_path
    expect(page).to have_text("Payment ##{payment.id}")
    expect(page).to have_css("tr", text: "deliver")
    expect(page).to have_css("tr .muted", text: "direct (bypassed events)")
    shipment_rows = page.all("table.operations tbody tr").map(&:text)
                        .select { |text| text.include?("Shipment ##{shipment.id}") }
    expect(shipment_rows.length).to eq(3)
    expect(shipment_rows[0]).to include("ship")
    expect(shipment_rows[1]).to include("pack")
    expect(shipment_rows[2]).to include("deliver")
  end
end
