# frozen_string_literal: true

require "rails_helper"

# catalog: 39-checkout-flow
# catalog: 40-customer-statuses

RSpec.describe "the storefront", type: :system do
  it "walks catalog -> cart -> checkout -> Pay -> human statuses, no gem vocabulary" do
    visit products_path
    expect(page).to have_text("Walnut desk")
    expect(page).to have_text("$799.00")

    within("tr", text: "Reading lamp") { click_button "Add to cart" }
    within("tr", text: "Wool rug") { click_button "Add to cart" }

    visit cart_path
    expect(page).to have_text("Reading lamp")
    expect(page).to have_text("Total: $409.00")

    click_link "Proceed to checkout"
    fill_in "customer_name", with: "Nora Woolf"
    check "express"
    click_button "Place the order"

    expect(page).to have_text("placed — thank you!")
    expect(page).to have_text("Awaiting payment")
    expect(page).to have_text("express delivery")
    expect(page).to have_text("Total: $409.00")

    click_button "Pay"

    expect(page).to have_text("Payment received — we are confirming it now.")
    expect(page).to have_text("Payment pending confirmation")
    expect(page).to have_no_button("Pay")

    visit my_orders_path
    expect(page).to have_text("Payment pending confirmation")
  end

  it "cancels with a reason in plain words, and refuses in plain words without one" do
    visit products_path
    within("tr", text: "Ceramic vase") { click_button "Add to cart" }
    visit checkout_path
    fill_in "customer_name", with: "Omar Reyes"
    click_button "Place the order"

    click_button "Cancel the order"
    expect(page).to have_text("We couldn't cancel this order")
    expect(page).to have_no_text("Refused:")
    expect(page).to have_no_text("GuardFailed")

    fill_in "metadata[reason]", with: "found a better lamp"
    click_button "Cancel the order"
    expect(page).to have_text("Your order has been cancelled.")
    expect(page).to have_text("Cancelled")
  end

  it "a credit checkout births a CreditOrder and says so on the card" do
    visit products_path
    within("tr", text: "Oak bookshelf") { click_button "Add to cart" }
    visit checkout_path
    fill_in "customer_name", with: "Petra Stein"
    check "credit"
    click_button "Place the order"

    expect(page).to have_text("paid on credit")
    expect(Order.order(:id).last).to be_a(CreditOrder)
  end
end
