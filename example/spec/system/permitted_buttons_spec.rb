# frozen_string_literal: true

require "rails_helper"

# catalog: 41-permissions-x-graph
# catalog: 26-toctou-gap

RSpec.describe "permitted buttons", type: :system do
  it "one pending order, three roles, three different button sets" do
    order = Order.find_by!(number: "ORD-1001")

    # Uma owns the order: the storefront card offers her Pay and Cancel.
    visit my_order_path(order)
    expect(page).to have_button("Pay")
    expect(page).to have_button("Cancel the order")

    # Mark works the desk: cancel is his, pay and the privileged paths are
    # not — the intersection strips them from the very same record.
    sign_in_as("Mark Manager (manager)")
    visit admin_order_path(order)
    within(".transition-buttons") do
      expect(page).to have_button("cancel")
      expect(page).to have_no_button("pay")
      expect(page).to have_no_button("admin_override")
    end
    expect(page).to have_no_button("bypass cancel")

    # Ada owns the whole surface, bypass included.
    sign_in_as("Ada Admin (admin)")
    visit admin_order_path(order)
    within(".transition-buttons", match: :first) do
      expect(page).to have_button("cancel")
      expect(page).to have_button("pay")
      expect(page).to have_button("admin_override")
    end
    expect(page).to have_button("bypass cancel")
  end

  it "TOCTOU survives the intersection: the snapshot ages between render and click" do
    sign_in_as("Ada Admin (admin)")
    order = Order.find_by!(number: "ORD-1004")
    visit admin_order_path(order)
    expect(page).to have_button("refund")

    OrderSeeds.ship_items(order)
    click_button "refund"

    expect(page).to have_text("Refused:")
    # The button stays — the graph edge and the right still exist; what died
    # is readiness, and the guard-aware panel says so.
    expect(page).to have_button("refund")
    expect(page).to have_no_css(".available-panel li", text: "refunded")
  end
end
