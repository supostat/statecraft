# frozen_string_literal: true

require "support/test_schema"

RSpec.describe "warning funnel and sqlite lock degradation" do
  before do
    TestSchema.load!
    ActiveRecord::Base.connection.execute("DELETE FROM orders")
    ActiveRecord::Base.connection.execute("DELETE FROM order_transitions")
    Statecraft.send(:reset_warning_dedup!)
  end

  describe "Statecraft.warn" do
    it "prints once per key per process with the statecraft prefix" do
      expect do
        Statecraft.warn(:probe_key, "first message")
        Statecraft.warn(:probe_key, "first message repeated")
      end.to output(/\A\[statecraft\] first message\n\z/).to_stderr
    end

    it "prints separately for distinct keys" do
      expect do
        Statecraft.warn(:key_one, "one")
        Statecraft.warn(:key_two, "two")
      end.to output(/one.*two/m).to_stderr
    end
  end

  describe "sqlite lock degradation" do
    def define_mounted_order
      stub_const("OrderFlow", Class.new do
        include Statecraft::Machine

        state :pending, initial: true
        state :cancelled
        state :paid
        transition from: :pending, to: :cancelled, lock: true
        transition from: :cancelled, to: :paid, lock: true
      end)
      stub_const("Order", Class.new(ActiveRecord::Base) { self.table_name = "orders" })
      stub_const("OrderTransition", Class.new(ActiveRecord::Base) do
        self.table_name = "order_transitions"

        def readonly? = persisted?
      end)
      Order.state_machine(OrderFlow)
    end

    before do
      skip "sqlite-only degradation scenario" if SpecDatabase.postgres?
    end

    it "completes the lock transition, still reloads, and warns exactly once per machine" do
      define_mounted_order
      order = Order.create!
      Order.where(id: order.id).update_all(status: "changed-behind-the-back")

      warnings = capture_stderr do
        order.transition_to!(:cancelled)
        order.transition_to!(:paid)
      end

      expect(order.status).to eq("changed-behind-the-back")
      expect(order.reload.state).to eq("paid")
      expect(warnings.scan("row locking unavailable on sqlite").length).to eq(1)
      expect(warnings).to include("OrderFlow")
    end

    it "keys the dedup by machine, so another machine warns on its own" do
      Statecraft.warn(%w[OrderFlow sqlite_row_lock], "row locking unavailable (OrderFlow)")
      expect do
        Statecraft.warn(%w[BillingFlow sqlite_row_lock], "row locking unavailable (BillingFlow)")
      end.to output(/BillingFlow/).to_stderr
    end

    def capture_stderr
      original = $stderr
      $stderr = StringIO.new
      yield
      $stderr.string
    ensure
      $stderr = original
    end
  end
end
