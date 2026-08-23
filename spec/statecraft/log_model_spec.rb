# frozen_string_literal: true

require "support/test_schema"

RSpec.describe "log model reading surface" do
  before do
    TestSchema.load!
    ActiveRecord::Base.connection.execute("DELETE FROM orders")
    ActiveRecord::Base.connection.execute("DELETE FROM order_transitions")
  end

  def define_mounted_order
    stub_const("OrderFlow", Class.new do
      include Statecraft::Machine

      state :pending, initial: true
      state :paid
      state :refunded
      event :pay, from: :pending, to: :paid
      event :refund, from: :paid, to: :refunded
    end)
    stub_const("Order", Class.new(ActiveRecord::Base) { self.table_name = "orders" })
    stub_const("OrderTransition", Class.new(ActiveRecord::Base) do
      self.table_name = "order_transitions"

      def readonly? = persisted?
    end)
    Order.state_machine(OrderFlow)
  end

  def insert_log_row(order, from:, to:, event: nil)
    OrderTransition.insert!(
      { order_id: order.id, from_state: from, to_state: to, event: event,
        metadata: {}, created_at: Time.current }
    )
  end

  describe "history" do
    it "returns the record's log rows ordered by id" do
      define_mounted_order
      order = Order.create!
      other = Order.create!
      insert_log_row(order, from: "pending", to: "paid", event: "pay")
      insert_log_row(other, from: "pending", to: "paid")
      insert_log_row(order, from: "paid", to: "refunded", event: "refund")

      expect(order.history.map(&:to_state)).to eq(%w[paid refunded])
      expect(order.history.to_sql).to include("ORDER BY")
    end

    it "is empty for a record without transitions" do
      define_mounted_order
      order = Order.create!
      expect(order.history).to be_empty
    end
  end

  describe "last_transition" do
    it "returns the newest log row by id" do
      define_mounted_order
      order = Order.create!
      insert_log_row(order, from: "pending", to: "paid", event: "pay")
      insert_log_row(order, from: "paid", to: "refunded", event: "refund")

      expect(order.last_transition.to_state).to eq("refunded")
    end
  end

  describe "in_state?" do
    it "compares the column value with symbol or string" do
      define_mounted_order
      order = Order.create!(state: "paid")
      expect(order.in_state?(:paid)).to be(true)
      expect(order.in_state?("paid")).to be(true)
      expect(order.in_state?(:pending)).to be(false)
    end
  end

  describe "readonly log rows (the generated-class contract)" do
    it "lets the insert path create rows" do
      define_mounted_order
      order = Order.create!
      expect { insert_log_row(order, from: "pending", to: "paid") }
        .to change(OrderTransition, :count).by(1)
    end

    it "rejects update! on a persisted row" do
      define_mounted_order
      order = Order.create!
      insert_log_row(order, from: "pending", to: "paid")
      row = order.history.last

      expect { row.update!(event: "tampered") }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it "rejects destroy on a persisted row" do
      define_mounted_order
      order = Order.create!
      insert_log_row(order, from: "pending", to: "paid")
      row = order.history.last

      expect { row.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end
  end
end
