# frozen_string_literal: true

require "rails_helper"

RSpec.describe MyOrdersQuery do
  it "returns only the owner's orders, newest first" do
    uma = User.find_by!(role: "user")
    mark = User.find_by!(role: "manager")
    marks = OrderSeeds.place_order(number: "SPEC-MQ-MARK", customer: mark.name,
                                   items: { "Reading lamp" => 1 }, user: mark)

    uma_numbers = described_class.call(user: uma).map(&:number)

    expect(uma_numbers).to include("ORD-1001")
    expect(uma_numbers).not_to include(marks.number)
    expect(described_class.call(user: mark).map(&:number)).to eq([marks.number])
  end
end
