# frozen_string_literal: true

require "support/test_schema"

RSpec.describe "re-entrancy guard" do
  before do
    TestSchema.load!
    ActiveRecord::Base.connection.execute("DELETE FROM orders")
    ActiveRecord::Base.connection.execute("DELETE FROM order_transitions")
  end

  def define_mounted(machine_body)
    stub_const("OrderFlow", Class.new do
      include Statecraft::Machine

      state :pending, initial: true
      state :paid
      state :cancelled
      class_eval(&machine_body)
    end)
    stub_const("Order", Class.new(ActiveRecord::Base) { self.table_name = "orders" })
    stub_const("OrderTransition", Class.new(ActiveRecord::Base) do
      self.table_name = "order_transitions"

      def readonly? = persisted?
    end)
    Order.state_machine(OrderFlow)
  end

  it "raises NestedTransitionError from before_transition on the same record" do
    define_mounted(proc do
      event :pay, from: :pending, to: :paid
      transition from: :pending, to: :cancelled
      before_transition ->(record, _transition) { record.transition_to!(:cancelled) }, event: [:pay]
    end)
    order = Order.create!

    expect { order.fire!(:pay) }
      .to raise_error(Statecraft::NestedTransitionError, /move it to after_transition/)
    expect(OrderTransition.count).to eq(0)
  end

  it "raises NestedTransitionError from a guard on the same record" do
    define_mounted(proc do
      event :pay, from: :pending, to: :paid, guard: ->(record, _metadata) { record.transition_to!(:cancelled) }
      transition from: :pending, to: :cancelled
    end)
    order = Order.create!

    expect { order.fire!(:pay) }.to raise_error(Statecraft::NestedTransitionError)
  end

  it "keys by record, not by instance: a fresh instance of the same record is caught" do
    define_mounted(proc do
      event :pay, from: :pending, to: :paid
      transition from: :pending, to: :cancelled
      before_transition lambda { |record, _transition|
        Order.find(record.id).transition_to!(:cancelled)
      }, event: [:pay]
    end)
    order = Order.create!

    expect { order.fire!(:pay) }.to raise_error(Statecraft::NestedTransitionError)
  end

  it "allows transitioning a different record from before_transition" do
    define_mounted(proc do
      event :pay, from: :pending, to: :paid
      transition from: :pending, to: :cancelled
      before_transition lambda { |record, _transition|
        sibling = Order.where.not(id: record.id).first
        sibling.transition_to!(:cancelled)
      }, event: [:pay]
    end)
    order = Order.create!
    sibling = Order.create!

    order.fire!(:pay)

    expect(order.reload.state).to eq("paid")
    expect(sibling.reload.state).to eq("cancelled")
  end

  it "allows a transition from after_commit as an independent pipeline" do
    define_mounted(proc do
      event :pay, from: :pending, to: :paid
      transition from: :paid, to: :cancelled
      after_commit ->(record, transition) { record.transition_to!(:cancelled) if transition.event == :pay }
    end)
    order = Order.create!

    order.fire!(:pay)

    expect(order.reload.state).to eq("cancelled")
    expect(OrderTransition.count).to eq(2)
  end
end
