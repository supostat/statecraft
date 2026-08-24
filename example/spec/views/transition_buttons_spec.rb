# frozen_string_literal: true

require "rails_helper"

# catalog: 24-graph-gates-render

# The partial renders the PERMITTED PREDICTION: the real machine's
# available_transitions crossed with a REAL Ability. Only the transport of
# can? into the test view context is stubbed — the Ability object itself is
# the production one.
RSpec.describe "shared/_transition_buttons", type: :view do
  def render_buttons_as(role_name, order)
    ability = Ability.new(User.find_by!(role: role_name))
    without_partial_double_verification do
      allow(view).to receive(:can?) { |action, subject| ability.can?(action, subject) }
    end
    render partial: "shared/transition_buttons", locals: {
      record: order,
      fire_url: ->(event_name) { "/probe/#{event_name}" }
    }
    rendered
  end

  it "renders different sets for different roles over the same record" do
    order = OrderSeeds.place_order(number: "SPEC-VIEW-PB", customer: "View Spec",
                                   items: { "Reading lamp" => 1 })

    manager_html = render_buttons_as("manager", order)
    expect(manager_html).to include('action="/probe/cancel"')
    expect(manager_html).not_to include('action="/probe/admin_override"')
    expect(manager_html).not_to include('action="/probe/pay"')

    admin_html = render_buttons_as("admin", order)
    expect(admin_html).to include('action="/probe/cancel"')
    expect(admin_html).to include('action="/probe/admin_override"')
    expect(admin_html).to include('action="/probe/pay"')
  end

  it "renders nothing when the machine allows nothing from here" do
    order = OrderSeeds.place_order(number: "SPEC-VIEW-DONE", customer: "View Spec",
                                   items: { "Reading lamp" => 1 })
    order.admin_override!

    expect(render_buttons_as("admin", order.reload)).not_to include("<button")
  end
end
