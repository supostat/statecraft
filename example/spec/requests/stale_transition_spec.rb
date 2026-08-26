# frozen_string_literal: true

require "rails_helper"

# The ABA scene: the operator's card rendered a seen token, the record's
# version moved on behind their back, and the submitted action bounces with
# the staleness words — nothing is written. The neighbour's full cycle is
# simulated past the pipeline, the way the gem's own conflict specs do it.
RSpec.describe "stale transitions", type: :request do
  it "refuses a cancel submitted from an outdated card and keeps the state" do
    operator = User.find_by!(role: "manager")
    post switch_user_path, params: { user_id: operator.id }

    order = OrderSeeds.place_order(number: "ORD-STALE", customer: "Stale Steve",
                                   items: { "Reading lamp" => 1 })
    rendered_token = order[:state_version]

    # A neighbour's cycle behind the open page: the state is back to
    # pending, but the version has moved on.
    Order.where(id: order.id).update_all(state_version: rendered_token + 3)

    post cancel_admin_order_path(order),
         params: { seen: rendered_token, metadata: { reason: "changed my mind" } }

    expect(response).to redirect_to(admin_order_path(order))
    expect(flash[:alert]).to include("outdated card")
    expect(order.reload[:state]).to eq("pending")
    expect(order.history).to be_empty
  end

  it "cancels cleanly when the token matches the row" do
    operator = User.find_by!(role: "manager")
    post switch_user_path, params: { user_id: operator.id }

    order = OrderSeeds.place_order(number: "ORD-FRESH", customer: "Fresh Fran",
                                   items: { "Reading lamp" => 1 })

    post cancel_admin_order_path(order),
         params: { seen: order[:state_version], metadata: { reason: "changed my mind" } }

    expect(response).to redirect_to(admin_order_path(order))
    expect(order.reload[:state]).to eq("cancelled")
    expect(order[:state_version]).to eq(1)
  end
end
