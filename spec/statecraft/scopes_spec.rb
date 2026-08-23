# frozen_string_literal: true

require "support/test_schema"

RSpec.describe "state scopes" do
  before do
    TestSchema.load!
    ActiveRecord::Base.connection.execute("DELETE FROM orders")
  end

  def define_flow
    stub_const("OrderFlow", Class.new do
      include Statecraft::Machine

      state :pending, initial: true
      state :paid
      event :pay, from: :pending, to: :paid
    end)
  end

  def define_order
    stub_const("Order", Class.new(ActiveRecord::Base) { self.table_name = "orders" })
    stub_const("OrderTransition", Class.new(ActiveRecord::Base) { self.table_name = "order_transitions" })
  end

  it "generates one flat scope per state when scopes: true" do
    define_flow
    define_order
    Order.state_machine(OrderFlow, scopes: true)
    Order.create!(state: "pending")
    Order.create!(state: "pending")
    Order.create!(state: "paid")

    expect(Order.pending.count).to eq(2)
    expect(Order.paid.count).to eq(1)
  end

  it "builds the scope as a plain where on the column with zero joins" do
    define_flow
    define_order
    Order.state_machine(OrderFlow, scopes: true)

    sql = Order.pending.to_sql
    expect(sql).to include(%("orders"."state"))
    expect(sql.downcase).not_to include("join")
  end

  it "generates no scopes when scopes stays off" do
    define_flow
    define_order
    Order.state_machine(OrderFlow)
    expect(Order).not_to respond_to(:pending)
  end

  it "respects a custom column:" do
    define_flow
    define_order
    Order.state_machine(OrderFlow, column: :status, scopes: true)
    Order.create!(status: "pending")
    Order.create!(status: "paid")

    expect(Order.paid.count).to eq(1)
    expect(Order.paid.to_sql).to include(%("orders"."status"))
  end

  it "refuses to shadow an existing class method" do
    define_flow
    stub_const("Order", Class.new(ActiveRecord::Base) do
      self.table_name = "orders"

      def self.paid = :existing
    end)
    stub_const("OrderTransition", Class.new(ActiveRecord::Base) { self.table_name = "order_transitions" })

    expect { Order.state_machine(OrderFlow, scopes: true) }
      .to raise_error(Statecraft::CompilationError, /scope paid conflicts/)
  end
end
