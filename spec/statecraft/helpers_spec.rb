# frozen_string_literal: true

require "support/test_schema"

RSpec.describe "verb helpers" do
  before do
    TestSchema.load!
    ActiveRecord::Base.connection.execute("DELETE FROM orders")
    ActiveRecord::Base.connection.execute("DELETE FROM order_transitions")
  end

  def define_mounted_order(helpers:)
    stub_const("OrderFlow", Class.new do
      include Statecraft::Machine

      state :pending, initial: true
      state :paid
      event :pay, from: :pending, to: :paid, guard: ->(_record, metadata) { metadata["amount"].to_i.positive? }
    end)
    stub_const("Order", Class.new(ActiveRecord::Base) { self.table_name = "orders" })
    stub_const("OrderTransition", Class.new(ActiveRecord::Base) do
      self.table_name = "order_transitions"

      def readonly? = persisted?
    end)
    Order.state_machine(OrderFlow, helpers: helpers)
  end

  it "runs the bang verb through the real pipeline and returns the log record" do
    define_mounted_order(helpers: true)
    order = Order.create!

    log_record = order.pay!(metadata: { amount: 5 })

    expect(log_record).to be_a(OrderTransition)
    expect(order.reload.state).to eq("paid")
    expect(order.history.map(&:event)).to eq(["pay"])
  end

  it "returns false from the non-bang verb on a guard refusal" do
    define_mounted_order(helpers: true)
    order = Order.create!
    expect(order.pay(metadata: { amount: 0 })).to be(false)
    expect(order.reload.state).to eq("pending")
  end

  it "keeps may_ verbs aligned with can_fire?" do
    define_mounted_order(helpers: true)
    order = Order.create!

    expect(order.may_pay?(metadata: { amount: 5 })).to eq(order.can_fire?(:pay, metadata: { amount: 5 }))
    expect(order.may_pay?(metadata: { amount: 0 })).to eq(order.can_fire?(:pay, metadata: { amount: 0 }))
  end

  it "generates no verbs when helpers stay off" do
    define_mounted_order(helpers: false)
    order = Order.create!
    expect(order).not_to respond_to(:pay!)
    expect(order).not_to respond_to(:pay)
    expect(order).not_to respond_to(:may_pay?)
    expect(order.can_fire?(:pay, metadata: { amount: 5 })).to be(true)
  end
end
