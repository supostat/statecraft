# frozen_string_literal: true

require "rails_helper"

# catalog: 23-triple-path-edge
# catalog: 27-sti-shared-machine

RSpec.describe OrderFlow do
  describe "mounting" do
    it "refuses a second mount" do
      expect { Order.state_machine(OrderFlow) }.to raise_error(Statecraft::AlreadyMounted)
    end
  end

  describe "the triple-path edge" do
    it "writes three distinguishable log rows for the one pending -> cancelled edge" do
      by_event = Order.create!(number: "SPEC-PATH-EVENT")
      by_event.cancel!(metadata: { "reason" => "spec" })
      by_override = Order.create!(number: "SPEC-PATH-OVERRIDE")
      by_override.admin_override!
      by_bypass = Order.create!(number: "SPEC-PATH-BYPASS")
      by_bypass.transition_to!(:cancelled, bypass_events: true)

      expect(by_event.last_transition.event).to eq("cancel")
      expect(by_override.last_transition.event).to eq("admin_override")
      expect(by_bypass.last_transition.event).to be_nil
    end

    it "exposes both event names on the edge's static shape" do
      edge = OrderFlow.transitions_from(:pending).find { |descriptor| descriptor[:to] == :cancelled }
      expect(edge[:events]).to eq(%i[cancel admin_override])
    end

    it "refuses a bare direct transition on the guarded-events edge" do
      order = Order.create!(number: "SPEC-NO-BARE-DIRECT")
      expect { order.transition_to!(:cancelled) }.to raise_error(Statecraft::InvalidTransition, /bypass_events/)
    end
  end

  describe "one guard, two STI types" do
    it "refuses cancel for different reasons: missing metadata vs the type itself" do
      plain = Order.create!(number: "SPEC-PLAIN")
      credit = CreditOrder.create!(number: "SPEC-CREDIT")

      expect { plain.cancel!(metadata: {}) }.to raise_error(Statecraft::GuardFailed)
      expect(plain.cancel!(metadata: { "reason" => "ok" })).to be_a(OrderTransition)
      expect { credit.cancel!(metadata: { "reason" => "ok" }) }.to raise_error(Statecraft::GuardFailed)
    end

    it "keeps STI descendants visible through the class-level scopes" do
      CreditOrder.create!(number: "SPEC-SCOPE-CREDIT")
      expect(Order.pending.map(&:number)).to include("SPEC-SCOPE-CREDIT")
    end
  end
end
