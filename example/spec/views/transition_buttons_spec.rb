# frozen_string_literal: true

require "rails_helper"

# The real-dep smoke of the skeleton -> gem edge: the partial renders from the
# ACTUAL Machine.transitions_from of an actual machine class — the graph gates
# the render, and guards are never consulted for it.
RSpec.describe "shared/_transition_buttons", type: :view do
  def machine_with_doubled_edge
    Class.new do
      include Statecraft::Machine

      state :pending, initial: true
      state :paid
      state :cancelled

      event :pay, from: :pending, to: :paid,
                  guard: ->(_record, _metadata) { raise "guards must not be consulted by the shape" }
      event :cancel, from: :pending, to: :cancelled
      event :void, from: :pending, to: :cancelled
    end
  end

  def render_buttons(machine, state)
    render partial: "shared/transition_buttons", locals: {
      machine: machine, state: state,
      fire_url: ->(event_name) { "/probe/#{event_name}" }
    }
  end

  it "renders one button per event name, both names of a doubled edge included" do
    render_buttons(machine_with_doubled_edge, :pending)

    expect(rendered).to include('action="/probe/pay"')
    expect(rendered).to include('action="/probe/cancel"')
    expect(rendered).to include('action="/probe/void"')
  end

  it "renders no buttons for a state outside the graph" do
    render_buttons(machine_with_doubled_edge, :ghost)

    expect(rendered).not_to include("<form")
  end
end
