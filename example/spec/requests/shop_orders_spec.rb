# frozen_string_literal: true

require "rails_helper"

# catalog: 35-namespaced-runtime

# The runtime half of the namespaced story: the generator's output, kept
# as-is, mounts and transitions in a live app — no routes involved, the
# subject is the machinery itself.
RSpec.describe "the generated Shop::Order runtime" do
  it "mounts with the namespaced log convention" do
    mounting = Shop::Order.statecraft_mounting
    expect(mounting.machine_class).to eq(Shop::OrderFlow)
    expect(Shop::Order.new.history).to be_a(ActiveRecord::Relation)
  end

  it "transitions through the generated machine and logs into Shop::OrderTransition" do
    order = Shop::Order.create!

    expect { order.pay!(metadata: {}) }.to raise_error(Statecraft::GuardFailed)

    log_row = order.pay!(metadata: { "amount" => 100 })

    expect(order[:state]).to eq("paid")
    expect(log_row).to be_a(Shop::OrderTransition)
    expect(log_row.event).to eq("pay")
    expect(Shop::OrderTransition.where(order_id: order.id).count).to eq(1)
  end

  it "keeps the generated surface: verbs, scopes and changed_at" do
    order = Shop::Order.create!
    expect(order.may_pay?(metadata: { "amount" => 1 })).to be(true)
    expect(Shop::Order.pending).to include(order)

    order.pay!(metadata: { "amount" => 1 })

    expect(order.state_changed_at).to be_present
    expect(Shop::Order.paid).to include(order)
  end
end
