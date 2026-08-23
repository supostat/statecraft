# frozen_string_literal: true

require "support/test_schema"

RSpec.describe "instrumentation" do
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
      event :pay, from: :pending, to: :paid, guard: :payable?
      transition from: :pending, to: :cancelled, lock: true

      def payable?(_record, metadata) = metadata["amount"].to_i.positive?
    end)
    stub_const("Order", Class.new(ActiveRecord::Base) { self.table_name = "orders" })
    stub_const("OrderTransition", Class.new(ActiveRecord::Base) do
      self.table_name = "order_transitions"

      def readonly? = persisted?
    end)
    Order.state_machine(OrderFlow)
  end

  def subscribe(event_name)
    received = []
    subscriber = ActiveSupport::Notifications.subscribe(event_name) do |_name, started, finished, _id, payload|
      received << { started: started, finished: finished, payload: payload }
    end
    yield received
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  describe "transition.statecraft" do
    it "publishes the success payload without metadata" do
      subscribe("transition.statecraft") do |received|
        order = Order.create!
        order.fire!(:pay, metadata: { amount: 5, secret: "pii" })

        expect(received.length).to eq(1)
        payload = received.first[:payload]
        expect(payload).to eq(
          record_class: "Order", record_id: order.id, machine: "OrderFlow",
          from: :pending, to: :paid, event: :pay
        )
        expect(payload).not_to have_key(:metadata)
      end
    end

    it "carries manual timing: finished at or after started" do
      subscribe("transition.statecraft") do |received|
        Order.create!.fire!(:pay, metadata: { amount: 5 })
        timing = received.first
        expect(timing[:finished]).to be >= timing[:started]
      end
    end

    it "publishes nothing on a refused transition" do
      subscribe("transition.statecraft") do |received|
        order = Order.create!
        order.fire(:pay, metadata: { amount: 0 })
        expect(received).to be_empty
      end
    end
  end

  describe "transition_failed.statecraft" do
    it "reports a guard refusal with the guard name" do
      subscribe("transition_failed.statecraft") do |received|
        order = Order.create!
        order.fire(:pay, metadata: { amount: 0 })

        payload = received.first[:payload]
        expect(payload[:reason]).to eq(:guard_failed)
        expect(payload[:guard]).to eq(:payable?)
        expect(payload[:machine]).to eq("OrderFlow")
      end
    end

    it "reports a conflict with the expected from" do
      subscribe("transition_failed.statecraft") do |received|
        order = Order.create!
        Order.where(id: order.id).update_all(state: "cancelled")
        begin
          order.fire!(:pay, metadata: { amount: 1 })
        rescue Statecraft::TransitionConflict
          nil
        end

        payload = received.first[:payload]
        expect(payload[:reason]).to eq(:conflict)
        expect(payload[:expected_from]).to eq(:pending)
      end
    end

    it "reports an invalid transition with the requested target" do
      subscribe("transition_failed.statecraft") do |received|
        order = Order.create!(state: "paid")
        order.transition_to(:pending)

        payload = received.first[:payload]
        expect(payload[:reason]).to eq(:invalid_transition)
        expect(payload[:requested]).to eq(:pending)
      end
    end

    it "publishes the refusal outside any transaction, after the rollback" do
      transaction_open = nil
      subscribe("transition_failed.statecraft") do |_received|
        probe = ActiveSupport::Notifications.subscribe("transition_failed.statecraft") do |*_args|
          transaction_open = ActiveRecord::Base.connection.transaction_open?
        end
        begin
          order = Order.create!
          Order.where(id: order.id).update_all(state: "cancelled")
          begin
            order.fire!(:pay, metadata: { amount: 1 })
          rescue Statecraft::TransitionConflict
            nil
          end
        ensure
          ActiveSupport::Notifications.unsubscribe(probe)
        end
      end

      expect(transaction_open).to be(false)
    end

    it "stays silent on programmer errors" do
      subscribe("transition_failed.statecraft") do |received|
        expect { Order.new.transition_to!(:cancelled) }
          .to raise_error(Statecraft::UnsavedRecordError)

        dirty = Order.create!
        dirty.status = "tampered"
        expect { dirty.transition_to!(:cancelled) }
          .to raise_error(Statecraft::DirtyRecordError)

        expect(received).to be_empty
      end
    end
  end
end
