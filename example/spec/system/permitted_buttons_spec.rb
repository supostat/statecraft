# frozen_string_literal: true

require "rails_helper"

# catalog: 41-permissions-x-graph
# catalog: 26-toctou-gap
# catalog: 43-record-layer-offering

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

  it "a credit order offers cancel to no one: the record layer strips it before rights" do
    credit = CreditOrder.create!(number: "SPEC-CREDIT-BTN", customer_name: "Spec",
                                 user: User.find_by!(role: "user"))

    # Uma owns it, yet the storefront cancel form is gone: the machine does
    # not offer this type the event, whatever the role.
    visit my_order_path(credit)
    expect(page).to have_button("Pay")
    expect(page).to have_no_button("Cancel the order")

    # Ada holds every right there is — the offering still excludes cancel;
    # her paths onto that edge are the privileged ones.
    sign_in_as("Ada Admin (admin)")
    visit admin_order_path(credit)
    within(".transition-buttons", match: :first) do
      expect(page).to have_button("pay")
      expect(page).to have_button("admin_override")
      expect(page).to have_no_button("cancel")
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
    # The re-render took a FRESH record-layer snapshot: the offering no
    # longer includes refund and the panel agrees — the stale button lived
    # exactly in the gap between the old render and the click.
    expect(page).to have_no_button("refund")
    expect(page).to have_no_css(".available-panel li", text: "refunded")
  end
end
