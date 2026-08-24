# frozen_string_literal: true

require "rails_helper"

RSpec.describe OrdersQuery do
  it "filters by a known state scope, descendants included" do
    numbers = described_class.call(state: "paid").map(&:number)

    expect(numbers).to include("ORD-1002", "ORD-1003")
    expect(numbers).not_to include("ORD-1006")
  end

  it "treats an unknown or empty state as all, ordered by number" do
    all_numbers = described_class.call.map(&:number)
    expect(all_numbers).to eq(all_numbers.sort)
    expect(described_class.call(state: "bogus").count).to eq(all_numbers.length)
  end
end
