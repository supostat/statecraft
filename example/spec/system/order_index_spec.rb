# frozen_string_literal: true

require "rails_helper"

RSpec.describe "the order index", type: :system do
  it "mixes both STI types in one list" do
    visit orders_path

    expect(page).to have_link("ORD-PAID")
    expect(page).to have_link("ORD-CREDIT-PAID")
    expect(page).to have_css("td", text: "credit")
    expect(page).to have_css("td", text: "regular")
  end

  it "filters by the state scopes, and a scope sees STI descendants" do
    visit orders_path(state: "cancelled")
    expect(page).to have_link("ORD-CANCELLED-EVENT")
    expect(page).to have_no_link("ORD-PAID")

    visit orders_path(state: "paid")
    expect(page).to have_link("ORD-PAID")
    expect(page).to have_link("ORD-CREDIT-PAID")
  end
end
