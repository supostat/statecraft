# frozen_string_literal: true

require "rails_helper"

# The seeded world never has empty shelves (order items hold FK references
# to products), so the empty state is proven at the view layer.
RSpec.describe "products/index", type: :view do
  it "shows the calm empty shelves line when the catalog is empty" do
    assign(:products, [])
    render
    expect(rendered).to include("Nothing on the shelves yet.")
  end
end
