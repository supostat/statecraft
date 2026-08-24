# frozen_string_literal: true

require "rails_helper"

RSpec.describe "the admin page", type: :system do
  it "bypass writes event: nil and the history shows the muted direct label" do
    order = Order.create!(number: "SPEC-ADMIN-BYPASS")
    visit admin_order_path(order)
    expect(page).to have_text("Bypass writes event: nil")

    click_button "bypass cancel"

    expect(page).to have_text("bypassed: the order is now cancelled")
    expect(page).to have_css(".history .muted", text: "direct (bypassed events)")
  end

  it "admin_override is a named event and the history says so — distinguishable from bypass" do
    order = Order.create!(number: "SPEC-ADMIN-OVERRIDE")
    visit admin_order_path(order)

    click_button "admin_override"

    expect(page).to have_text("admin_override fired: the order is now cancelled")
    expect(page).to have_css(".history td", text: "admin_override")
    expect(page).to have_no_css(".history .muted", text: "direct (bypassed events)")
  end
end
