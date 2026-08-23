# frozen_string_literal: true

require "support/test_schema"

RSpec.describe "transition pipeline" do
  before do
    TestSchema.load!
    ActiveRecord::Base.connection.execute("DELETE FROM orders")
    ActiveRecord::Base.connection.execute("DELETE FROM order_transitions")
    define_mounted_order
  end

  def define_mounted_order(mount_options = {})
    stub_const("OrderFlow", Class.new do
      include Statecraft::Machine

      state :pending, initial: true
      state :paid
      state :cancelled
      state :flagged

      event :pay, from: :pending, to: :paid, guard: :payable?
      transition from: :pending, to: :cancelled, guard: :cancellable?
      transition from: :paid, to: :paid
      transition from: :pending, to: :flagged, lock: true

      def payable?(_record, metadata) = metadata["amount"].to_i.positive?
      def cancellable?(_record, _metadata) = true
    end)
    stub_const("Order", Class.new(ActiveRecord::Base) { self.table_name = "orders" })
    stub_const("OrderTransition", Class.new(ActiveRecord::Base) do
      self.table_name = "order_transitions"

      def readonly? = persisted?
    end)
    Order.state_machine(OrderFlow, **mount_options)
  end

  describe "the pipeline order and runtime errors" do
    it "raises UnsavedRecordError as the very first step" do
      expect { Order.new.transition_to!(:cancelled) }
        .to raise_error(Statecraft::UnsavedRecordError, /save the record first/)
    end

    it "raises DirtyRecordError on a lock edge with unsaved changes" do
      order = Order.create!
      order.status = "tampered"
      expect { order.transition_to!(:flagged) }
        .to raise_error(Statecraft::DirtyRecordError, /unsaved changes.*status/)
    end

    it "allows a dirty record on an unlocked edge and does not save foreign changes" do
      order = Order.create!
      order.status = "tampered"
      order.transition_to!(:cancelled)
      expect(order.reload.status).to eq("draft")
    end

    it "raises InvalidTransition with the allowed list for an undeclared edge" do
      order = Order.create!(state: "cancelled")
      expect { order.transition_to!(:paid) }
        .to raise_error(Statecraft::InvalidTransition, /allowed from cancelled: none/)
    end

    it "fails the guard before writing anything" do
      order = Order.create!
      expect { order.fire!(:pay, metadata: { amount: 0 }) }
        .to raise_error(Statecraft::GuardFailed, /payable\?/)
      expect(OrderTransition.count).to eq(0)
      expect(order.reload.state).to eq("pending")
    end

    it "raises TransitionConflict with the expected from when another writer won" do
      order = Order.create!
      Order.where(id: order.id).update_all(state: "cancelled")
      expect { order.fire!(:pay, metadata: { amount: 1 }) }
        .to raise_error(Statecraft::TransitionConflict, /expected state :pending/)
      expect(OrderTransition.count).to eq(0)
    end

    it "raises TransitionConflict when the lock reload reveals a foreign write" do
      order = Order.create!
      Order.where(id: order.id).update_all(state: "cancelled")
      expect { order.transition_to!(:flagged) }
        .to raise_error(Statecraft::TransitionConflict, /expected state :pending/)
      expect(OrderTransition.count).to eq(0)
    end

    it "raises TransitionConflict instead of silently running another declared edge" do
      stub_const("RerouteFlow", Class.new do
        include Statecraft::Machine

        state :pending, initial: true
        state :cancelled
        state :flagged

        transition from: :pending, to: :flagged, lock: true
        transition from: :cancelled, to: :flagged, lock: true
      end)
      stub_const("Order", Class.new(ActiveRecord::Base) { self.table_name = "orders" })
      Order.state_machine(RerouteFlow, log: OrderTransition)

      order = Order.create!
      Order.where(id: order.id).update_all(state: "cancelled")
      expect { order.transition_to!(:flagged) }
        .to raise_error(Statecraft::TransitionConflict, /expected state :pending/)
      expect(OrderTransition.count).to eq(0)
    end

    it "raises CompositePrimaryKeyUnsupported at the first transition, after a clean mounting" do
      stub_const("CompositeOrder", Class.new(ActiveRecord::Base) do
        self.table_name = "orders"
        self.primary_key = %w[id state]
      end)
      CompositeOrder.state_machine(OrderFlow, log: OrderTransition)
      Order.create!
      composite = CompositeOrder.first
      expect { composite.transition_to!(:cancelled) }
        .to raise_error(Statecraft::CompositePrimaryKeyUnsupported, /single-column/)
    end
  end

  describe "bang and non-bang semantics" do
    it "returns the created log record from the bang variant" do
      order = Order.create!
      log_record = order.fire!(:pay, metadata: { amount: 5 })
      expect(log_record).to be_a(OrderTransition)
      expect(log_record.from_state).to eq("pending")
      expect(log_record.to_state).to eq("paid")
      expect(log_record.event).to eq("pay")
    end

    it "returns the log record from non-bang on success" do
      order = Order.create!
      expect(order.fire(:pay, metadata: { amount: 5 })).to be_a(OrderTransition)
    end

    it "returns false from non-bang on GuardFailed" do
      order = Order.create!
      expect(order.fire(:pay, metadata: { amount: 0 })).to be(false)
    end

    it "returns false from non-bang on InvalidTransition" do
      order = Order.create!(state: "cancelled")
      expect(order.transition_to(:paid)).to be(false)
    end

    it "always raises TransitionConflict, including non-bang" do
      order = Order.create!
      Order.where(id: order.id).update_all(state: "cancelled")
      expect { order.fire(:pay, metadata: { amount: 1 }) }
        .to raise_error(Statecraft::TransitionConflict)
    end

    it "always raises TransitionConflict on the lock path, including non-bang" do
      order = Order.create!
      Order.where(id: order.id).update_all(state: "cancelled")
      expect { order.transition_to(:flagged) }
        .to raise_error(Statecraft::TransitionConflict)
    end

    it "always raises UnsavedRecordError, including non-bang" do
      expect { Order.new.transition_to(:cancelled) }
        .to raise_error(Statecraft::UnsavedRecordError)
    end
  end

  describe "bypass policy" do
    it "refuses a direct transition over an event-guarded edge" do
      order = Order.create!
      expect { order.transition_to!(:paid) }
        .to raise_error(Statecraft::InvalidTransition, /guarded by event pay.*bypass_events/)
    end

    it "passes with bypass_events: true, skips event guards and logs event nil" do
      order = Order.create!
      log_record = order.transition_to!(:paid, bypass_events: true, metadata: { amount: 0 })
      expect(log_record.event).to be_nil
      expect(order.state).to eq("paid")
    end

    it "still runs edge guards under bypass" do
      order = Order.create!
      log_record = order.transition_to!(:cancelled)
      expect(log_record.event).to be_nil
    end
  end

  describe "loops" do
    it "runs a from == to loop through CAS and writes a log row" do
      order = Order.create!(state: "paid")
      log_record = order.transition_to!(:paid)
      expect(log_record.from_state).to eq("paid")
      expect(log_record.to_state).to eq("paid")
      expect(order.history.count).to eq(1)
    end
  end

  describe "touch and changed_at" do
    it "touches updated_at inside the CAS update by default" do
      order = Order.create!(updated_at: 2.days.ago)
      previous_updated_at = order.updated_at
      order.transition_to!(:cancelled)
      expect(order.reload.updated_at).to be > previous_updated_at
    end

    it "does not touch updated_at with touch: false" do
      define_mounted_order(touch: false)
      order = Order.create!(updated_at: 2.days.ago)
      previous_updated_at = order.reload.updated_at
      order.transition_to!(:cancelled)
      expect(order.reload.updated_at).to be_within(1.second).of(previous_updated_at)
    end

    it "writes state_changed_at in the same update when the option is on" do
      define_mounted_order(changed_at: true)
      order = Order.create!
      order.transition_to!(:cancelled)
      expect(order.reload.state_changed_at).not_to be_nil
    end

    it "raises a clear error on the first transition when the option names a missing column" do
      define_mounted_order(changed_at: :missing_column)
      order = Order.create!
      expect { order.transition_to!(:cancelled) }
        .to raise_error(Statecraft::CompilationError, /missing_column does not exist/)
    end
  end

  describe "in-memory sync" do
    it "updates the attribute without a dirty mark" do
      order = Order.create!
      order.transition_to!(:cancelled)
      expect(order.state).to eq("cancelled")
      expect(order.changed?).to be(false)
    end
  end

  describe "the log insert path" do
    it "bypasses log-model validations and callbacks" do
      stub_const("StrictLog", Class.new(ActiveRecord::Base) do
        self.table_name = "order_transitions"

        validates :event, presence: true
        before_create { raise "log callback must never run" }

        def readonly? = persisted?
      end)
      stub_const("Order", Class.new(ActiveRecord::Base) { self.table_name = "orders" })
      Order.state_machine(OrderFlow, log: StrictLog)

      order = Order.create!
      log_record = order.transition_to!(:cancelled)
      expect(log_record.event).to be_nil
      expect(log_record).to be_persisted
    end
  end
end
