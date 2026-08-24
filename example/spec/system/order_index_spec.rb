# frozen_string_literal: true

require "rails_helper"

# catalog: 27-sti-shared-machine

RSpec.describe "the order index", type: :system do
  it "mixes both STI types in one list" do
    visit orders_path

    expect(page).to have_link("ORD-1002")
    expect(page).to have_link("ORD-1003")
    expect(page).to have_css("td", text: "credit")
    expect(page).to have_css("td", text: "regular")
  end

  it "filters by the state scopes, and a scope sees STI descendants" do
    visit orders_path(state: "cancelled")
    expect(page).to have_link("ORD-1006")
    expect(page).to have_no_link("ORD-1002")

    visit orders_path(state: "paid")
    expect(page).to have_link("ORD-1002")
    expect(page).to have_link("ORD-1003")
  end
end
