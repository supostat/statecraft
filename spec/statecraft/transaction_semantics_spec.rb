# frozen_string_literal: true

require "support/test_schema"

RSpec.describe "transaction semantics" do
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

      event :pay, from: :pending, to: :paid
      transition from: :pending, to: :cancelled

      before_transition :note_before
      after_commit :note_commit

      def note_before(record, _transition)
        record.class.where(id: record.id).update_all(status: "before-ran")
      end

      def note_commit(_record, transition)
        CommitProbe.calls << transition.to
      end
    end)
    stub_const("CommitProbe", Class.new do
      def self.calls = (@calls ||= [])
    end)
    stub_const("Order", Class.new(ActiveRecord::Base) { self.table_name = "orders" })
    stub_const("OrderTransition", Class.new(ActiveRecord::Base) do
      self.table_name = "order_transitions"

      def readonly? = persisted?
    end)
    Order.state_machine(OrderFlow)
  end

  describe "savepoint isolation" do
    it "rescuing TransitionConflict keeps the outer transaction's work intact" do
      order = Order.create!
      sibling = Order.create!
      Order.where(id: order.id).update_all(state: "cancelled")

      Order.transaction do
        sibling.update!(status: "outer-work")
        begin
          order.fire!(:pay)
        rescue Statecraft::TransitionConflict
          nil
        end
      end

      expect(sibling.reload.status).to eq("outer-work")
      expect(OrderTransition.count).to eq(0)
    end

    it "rolls back before_transition side effects when CAS conflicts" do
      order = Order.create!
      stale = Order.find(order.id)
      Order.where(id: order.id).update_all(state: "cancelled")

      begin
        stale.fire!(:pay)
      rescue Statecraft::TransitionConflict
        nil
      end

      expect(order.reload.status).not_to eq("before-ran")
    end

    it "commits the transition even when the caller rescues inside an outer transaction" do
      order = Order.create!
      Order.transaction do
        order.fire!(:pay)
      end
      expect(order.reload.state).to eq("paid")
      expect(OrderTransition.count).to eq(1)
    end

    it "rolls the in-memory state back with the savepoint when after_transition raises" do
      stub_const("ExplodingAfterFlow", Class.new do
        include Statecraft::Machine

        state :pending, initial: true
        state :paid
        event :pay, from: :pending, to: :paid
        after_transition :explode

        def explode(_record, _transition)
          raise "after bug"
        end
      end)
      stub_const("Order", Class.new(ActiveRecord::Base) { self.table_name = "orders" })
      Order.state_machine(ExplodingAfterFlow, log: OrderTransition)
      order = Order.create!

      expect { order.fire!(:pay) }.to raise_error(RuntimeError, "after bug")

      expect(order.state).to eq("pending")
      expect(order.changed?).to be(false)
      expect(order.reload.state).to eq("pending")
      expect(OrderTransition.count).to eq(0)
    end

    it "lets the caller retry cleanly after rescuing an after_transition failure" do
      stub_const("FlakyProbe", Class.new do
        def self.calls = (@calls ||= [])
      end)
      stub_const("FlakyAfterFlow", Class.new do
        include Statecraft::Machine

        state :pending, initial: true
        state :paid
        event :pay, from: :pending, to: :paid
        after_transition lambda { |_record, _transition|
          FlakyProbe.calls << :ran
          raise "flaky" if FlakyProbe.calls.length == 1
        }
      end)
      stub_const("Order", Class.new(ActiveRecord::Base) { self.table_name = "orders" })
      Order.state_machine(FlakyAfterFlow, log: OrderTransition)
      order = Order.create!

      expect { order.fire!(:pay) }.to raise_error(RuntimeError, "flaky")
      order.fire!(:pay)

      expect(order.state).to eq("paid")
      expect(order.reload.state).to eq("paid")
      expect(OrderTransition.count).to eq(1)
    end
  end

  describe "after_commit AR semantics" do
    it "runs after_commit callbacks after a standalone transition" do
      order = Order.create!
      order.fire!(:pay)
      expect(CommitProbe.calls).to eq([:paid])
    end

    it "defers after_commit to the outer real transaction's commit" do
      order = Order.create!
      Order.transaction do
        order.fire!(:pay)
        expect(CommitProbe.calls).to be_empty
      end
      expect(CommitProbe.calls).to eq([:paid])
    end

    it "never runs after_commit when the outer transaction rolls back" do
      order = Order.create!
      Order.transaction do
        order.fire!(:pay)
        raise ActiveRecord::Rollback
      end
      expect(CommitProbe.calls).to be_empty
      expect(order.reload.state).to eq("pending")
      expect(OrderTransition.count).to eq(0)
    end

    it "propagates an exception raised inside after_commit as-is" do
      stub_const("ExplodingFlow", Class.new do
        include Statecraft::Machine

        state :pending, initial: true
        state :paid
        event :pay, from: :pending, to: :paid
        after_commit :explode

        def explode(_record, _transition)
          raise "handler bug"
        end
      end)
      stub_const("Order", Class.new(ActiveRecord::Base) { self.table_name = "orders" })
      Order.state_machine(ExplodingFlow, log: OrderTransition)
      order = Order.create!

      expect { order.fire!(:pay) }.to raise_error(RuntimeError, "handler bug")
      expect(order.reload.state).to eq("paid")
    end
  end

  describe "passthrough of transaction-rollback errors" do
    it "lets ActiveRecord::TransactionRollbackError family pass through untouched" do
      order = Order.create!
      allow_any_instance_of(Statecraft::Pipeline)
        .to receive(:cas_update!).and_raise(ActiveRecord::Deadlocked, "deadlock found")

      expect { order.fire!(:pay) }.to raise_error(ActiveRecord::Deadlocked, "deadlock found")
    end
  end
end
