# frozen_string_literal: true

require "rails_helper"

# catalog: 28-staleness-two-mechanisms
# catalog: 29-dirty-save-and-capture

RSpec.describe "the operator payment desk", type: :system do
  before { sign_in_as("Ada Admin (admin)") }

  it "confirming a payment captures it AND pays the order — one visible two-step link" do
    order = Order.find_by!(number: "ORD-1012")
    payment = order.payment
    visit admin_payment_path(payment)

    click_button "capture"

    expect(page).to have_text("capture fired: the payment is captured and the order is paid.")
    expect(page).to have_css("code", text: "captured")
    expect(order.reload[:state]).to eq("paid")
  end

  it "dirty scene: save-and-capture refuses — don't mix persistence with a transition" do
    payment = Order.find_by!(number: "ORD-1012").payment
    visit admin_payment_path(payment)

    fill_in "payment[amount_cents]", with: "5100"
    click_button "save and capture"

    expect(page).to have_text("Refused:")
    expect(page).to have_text("save first, then capture")
    expect(page).to have_css("code", text: "pending")
  end

  it "two operators: a stale form's second submit meets the staleness flash, not a silent no-op" do
    payment = Order.find_by!(number: "ORD-1012").payment
    visit admin_payment_path(payment)

    # The second operator wins between this render and our click — an honest
    # pipeline capture on a fresh instance, out of band of the open page.
    Payment.find(payment.id).capture!(metadata: {})

    click_button "capture"

    expect(page).to have_text("This action is no longer available:")
    expect(page).to have_text("no branch from captured")
    expect(page).to have_css("code", text: "captured")
  end
end
