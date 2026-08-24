# frozen_string_literal: true

require "rails_helper"

# catalog: 42-role-switcher

RSpec.describe "the role switcher", type: :system do
  it "defaults to the seeded customer and shows who you are" do
    visit products_path

    expect(page).to have_select("user_id", selected: "Uma User (user)")
    expect(page).to have_no_link("Operations log")
  end

  it "switching roles through the nav changes rights and the admin zone's visibility" do
    visit admin_orders_path
    expect(page).to have_current_path(products_path)
    expect(page).to have_text("That area needs a different role")

    sign_in_as("Mark Manager (manager)")

    expect(page).to have_text("You are now Mark Manager (manager).")
    expect(page).to have_link("Operations log")
    visit admin_orders_path
    expect(page).to have_current_path(admin_orders_path)

    sign_in_as("Uma User (user)")
    visit admin_orders_path
    expect(page).to have_current_path(products_path)
  end
end
