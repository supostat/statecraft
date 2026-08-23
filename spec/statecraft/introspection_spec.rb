# frozen_string_literal: true

require "support/test_schema"

RSpec.describe "introspection" do
  before do
    TestSchema.load!
    ActiveRecord::Base.connection.execute("DELETE FROM orders")
    ActiveRecord::Base.connection.execute("DELETE FROM order_transitions")
    define_mounted_order
  end

  def define_mounted_order
    stub_const("OrderFlow", Class.new do
      include Statecraft::Machine

      state :pending, initial: true
      state :paid
      state :cancelled
      state :archived

      event :pay, from: :pending, to: :paid, guard: ->(_record, metadata) { metadata["amount"].to_i.positive? }
      transition from: :pending, to: :cancelled, guard: ->(_record, _metadata) { true }
      transition from: :paid, to: :archived
      event :pay_again, from: :paid, to: :paid
    end)
    stub_const("Order", Class.new(ActiveRecord::Base) { self.table_name = "orders" })
    stub_const("OrderTransition", Class.new(ActiveRecord::Base) do
      self.table_name = "order_transitions"

      def readonly? = persisted?
    end)
    Order.state_machine(OrderFlow)
  end

  describe "can_fire?" do
    it "answers per the guards with these metadata right now" do
      order = Order.create!
      expect(order.can_fire?(:pay, metadata: { amount: 5 })).to be(true)
      expect(order.can_fire?(:pay, metadata: { amount: 0 })).to be(false)
      expect(order.can_fire?(:pay)).to be(false)
    end

    it "returns false for an event with no branch from the current state" do
      order = Order.create!(state: "paid")
      expect(order.can_fire?(:pay)).to be(false)
    end

    it "returns false for an unknown event name" do
      order = Order.create!
      expect(order.can_fire?(:ghost_event)).to be(false)
    end
  end

  describe "available_events" do
    it "lists events whose branch exists and guards pass" do
      order = Order.create!
      expect(order.available_events(metadata: { amount: 5 })).to eq([:pay])
      expect(order.available_events).to eq([])
    end
  end

  describe "available_transitions" do
    it "reports to and via, with :direct only when the edge has no event guards" do
      order = Order.create!
      transitions = order.available_transitions(metadata: { amount: 5 })
      by_target = transitions.to_h { |availability| [availability.to, availability.via] }

      expect(by_target.fetch(:paid)).to eq([:pay])
      expect(by_target.fetch(:cancelled)).to eq([:direct])
    end

    it "drops an edge whose via is empty" do
      order = Order.create!
      transitions = order.available_transitions(metadata: { amount: 0 })
      expect(transitions.map(&:to)).to eq([:cancelled])
    end

    it "marks a bare edge as :direct" do
      order = Order.create!(state: "paid")
      transitions = order.available_transitions
      by_target = transitions.to_h { |availability| [availability.to, availability.via] }
      expect(by_target.fetch(:archived)).to eq([:direct])
      expect(by_target.fetch(:paid)).to eq(%i[pay_again direct])
    end
  end

  describe "transitioned_to?" do
    it "is strictly log-based: false for initial without a return" do
      order = Order.create!
      expect(order.transitioned_to?(:pending)).to be(false)
      expect(order.in_state?(:pending)).to be(true)
    end

    it "counts a loop as a real log row" do
      order = Order.create!(state: "paid")
      order.fire!(:pay_again)
      expect(order.transitioned_to?(:paid)).to be(true)
    end

    it "reads log rows with state names outside the graph" do
      order = Order.create!
      OrderTransition.insert!(
        { order_id: order.id, from_state: "ancient", to_state: "legacy_done",
          metadata: {}, created_at: Time.current }
      )
      expect(order.transitioned_to?(:legacy_done)).to be(true)
      expect(order.history.last.from_state).to eq("ancient")
    end
  end

  describe "new_record introspection" do
    it "answers from the attribute default without touching the pipeline" do
      order = Order.new
      expect(order.in_state?(:pending)).to be(true)
      expect(order.can_fire?(:pay, metadata: { amount: 5 })).to be(true)
      expect(order.available_events(metadata: { amount: 5 })).to eq([:pay])
      expect(order.history).to be_empty
    end
  end

  describe "normalization identity with the pipeline" do
    it "gives guards the round-tripped metadata in checks too" do
      seen = nil
      stub_const("ProbeFlow", Class.new do
        include Statecraft::Machine

        state :pending, initial: true
        state :paid
        event :pay, from: :pending, to: :paid, guard: lambda { |_record, metadata|
          seen = metadata
          true
        }
      end)
      stub_const("Order", Class.new(ActiveRecord::Base) { self.table_name = "orders" })
      Order.state_machine(ProbeFlow, log: OrderTransition)

      Order.create!.can_fire?(:pay, metadata: { reason: :fraud })
      expect(seen).to eq({ "reason" => "fraud" })
      expect(seen).to be_frozen
    end

    it "fails a mutating guard identically in check and transition" do
      stub_const("MutatingFlow", Class.new do
        include Statecraft::Machine

        state :pending, initial: true
        state :paid
        event :pay, from: :pending, to: :paid, guard: ->(_record, metadata) { metadata["sneak"] = 1 }
      end)
      stub_const("Order", Class.new(ActiveRecord::Base) { self.table_name = "orders" })
      Order.state_machine(MutatingFlow, log: OrderTransition)
      order = Order.create!

      expect { order.can_fire?(:pay, metadata: { a: 1 }) }.to raise_error(FrozenError)
      expect { order.fire!(:pay, metadata: { a: 1 }) }.to raise_error(FrozenError)
    end
  end
end
