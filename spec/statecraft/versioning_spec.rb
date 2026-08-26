# frozen_string_literal: true

require "support/test_schema"

# The tagged CAS: with versioning the pipeline compares-and-swaps on
# (state, version), which makes ABA visible — a state that went away and
# came back is not the state the caller saw. seen: carries the caller's
# snapshot; its refusal is StaleTransition, the 409 of the pipeline.
RSpec.describe "versioning" do
  before do
    TestSchema.load!
    ActiveRecord::Base.connection.execute("DELETE FROM orders")
    ActiveRecord::Base.connection.execute("DELETE FROM order_transitions")
    define_versioned_order
  end

  def define_versioned_order(versioning: true)
    stub_const("VersionedFlow", Class.new do
      include Statecraft::Machine

      state :pending, initial: true
      state :paid
      state :archived

      event :pay, from: :pending, to: :paid
      transition from: :pending, to: :archived
      transition from: :paid, to: :archived
    end)
    stub_const("Order", Class.new(ActiveRecord::Base) { self.table_name = "orders" })
    stub_const("OrderTransition", Class.new(ActiveRecord::Base) do
      self.table_name = "order_transitions"

      def readonly? = persisted?
    end)
    Order.state_machine(VersionedFlow, versioning: versioning)
  end

  def slip_past_the_pipeline(order, attributes)
    Order.where(id: order.id).update_all(attributes)
  end

  def define_versioned_order_with_helpers
    stub_const("HelperFlow", Class.new do
      include Statecraft::Machine

      state :pending, initial: true
      state :paid

      event :pay, from: :pending, to: :paid
      event :refund, from: :paid, to: :pending
    end)
    stub_const("Order", Class.new(ActiveRecord::Base) { self.table_name = "orders" })
    stub_const("OrderTransition", Class.new(ActiveRecord::Base) do
      self.table_name = "order_transitions"

      def readonly? = persisted?
    end)
    Order.state_machine(HelperFlow, versioning: true, helpers: true)
  end

  describe "the increment" do
    it "moves the version with every transition and mirrors it in memory" do
      order = Order.create!
      expect(order[:state_version]).to eq(0)

      order.fire!(:pay)
      expect(order[:state_version]).to eq(1)
      expect(order.reload[:state_version]).to eq(1)

      order.transition_to!(:archived)
      expect(order[:state_version]).to eq(2)
    end
  end

  describe "the tagged CAS without seen:" do
    it "catches ABA: the state came back, but the version moved on" do
      order = Order.create!
      slip_past_the_pipeline(order, state: "paid", state_version: 1)
      slip_past_the_pipeline(order, state: "pending", state_version: 2)

      expect { order.transition_to!(:archived) }.to raise_error(Statecraft::TransitionConflict) do |error|
        expect(error).not_to be_a(Statecraft::StaleTransition)
      end
    end

    it "conflicts when only the version moved under an unchanged state" do
      order = Order.create!
      slip_past_the_pipeline(order, state_version: 5)

      expect { order.fire!(:pay) }.to raise_error(Statecraft::TransitionConflict)
    end
  end

  describe "seen:" do
    it "passes with the token the row still holds" do
      order = Order.create!
      transition = order.fire!(:pay, seen: order[:state_version])

      expect(transition.to_state).to eq("paid")
      expect(order[:state_version]).to eq(1)
    end

    it "accepts the string form params deliver" do
      order = Order.create!
      expect(order.fire!(:pay, seen: "0")).to be_a(OrderTransition)
    end

    it "raises loudly on a garbage token" do
      order = Order.create!
      expect { order.fire!(:pay, seen: "not-a-version") }.to raise_error(ArgumentError)
    end

    it "refuses a stale token with StaleTransition carrying both fields" do
      order = Order.create!
      order.fire!(:pay)

      expect { order.transition_to!(:archived, seen: 0) }
        .to raise_error(Statecraft::StaleTransition) do |error|
          expect(error).to be_a(Statecraft::TransitionConflict)
          expect(error.expected_version).to eq(0)
          expect(error.seen).to eq(0)
          expect(error.message).to include("saw version 0")
        end
    end

    it "keeps raising through the non-bang forms" do
      order = Order.create!
      order.fire!(:pay)

      expect { order.transition_to(:archived, seen: 0) }
        .to raise_error(Statecraft::StaleTransition)
    end

    it "forwards seen: through the helper verbs" do
      define_versioned_order_with_helpers
      order = Order.create!

      expect(order.pay!(seen: 0)).to be_a(OrderTransition)
      expect { order.refund(seen: 0) }.to raise_error(Statecraft::StaleTransition)
    end

    it "refuses seen: on a mounting without versioning, naming the fix" do
      define_versioned_order(versioning: false)
      order = Order.create!

      expect { order.fire!(:pay, seen: 0) }
        .to raise_error(Statecraft::CompilationError, /seen: requires versioning: true/)
    end
  end

  describe "the configuration" do
    it "raises when the versioning column does not exist" do
      define_versioned_order(versioning: :ghost_version)
      order = Order.create!

      expect { order.fire!(:pay) }
        .to raise_error(Statecraft::CompilationError, /ghost_version does not exist on orders/)
    end
  end

  describe "the lock path" do
    def define_locked_order
      stub_const("LockedFlow", Class.new do
        include Statecraft::Machine

        state :pending, initial: true
        state :paid

        event :pay, from: :pending, to: :paid, lock: true
      end)
      stub_const("Order", Class.new(ActiveRecord::Base) { self.table_name = "orders" })
      stub_const("OrderTransition", Class.new(ActiveRecord::Base) do
        self.table_name = "order_transitions"

        def readonly? = persisted?
      end)
      Order.state_machine(LockedFlow, versioning: true)
    end

    it "sees the stale token deterministically after the reload" do
      define_locked_order
      order = Order.create!
      slip_past_the_pipeline(order, state: "paid", state_version: 1)
      slip_past_the_pipeline(order, state: "pending", state_version: 2)

      expect { order.fire!(:pay, seen: 0) }.to raise_error(Statecraft::StaleTransition)
    end
  end

  describe "chains" do
    it "lets an after_transition chain run, one increment per link" do
      stub_const("ChainedFlow", Class.new do
        include Statecraft::Machine

        state :pending, initial: true
        state :paid
        state :archived

        event :pay, from: :pending, to: :paid
        transition from: :paid, to: :archived

        after_transition(event: :pay) { |record| record.transition_to!(:archived) }
      end)
      stub_const("Order", Class.new(ActiveRecord::Base) { self.table_name = "orders" })
      stub_const("OrderTransition", Class.new(ActiveRecord::Base) do
        self.table_name = "order_transitions"

        def readonly? = persisted?
      end)
      Order.state_machine(ChainedFlow, versioning: true)

      order = Order.create!
      order.fire!(:pay, seen: 0)

      expect(order.reload[:state]).to eq("archived")
      expect(order[:state_version]).to eq(2)
      expect(order.history.count).to eq(2)
    end
  end

  describe "telemetry" do
    it "publishes reason :stale with both fields and never the parent's :conflict" do
      payloads = []
      subscription = ActiveSupport::Notifications.subscribe("transition_failed.statecraft") do |*args|
        payloads << args.last
      end

      order = Order.create!
      order.fire!(:pay)
      begin
        order.transition_to!(:archived, seen: 0, metadata: { "secret" => "pii" })
      rescue Statecraft::StaleTransition
        nil
      end

      expect(payloads.size).to eq(1)
      payload = payloads.first
      expect(payload[:reason]).to eq(:stale)
      expect(payload[:expected_version]).to eq(0)
      expect(payload[:seen]).to eq(0)
      expect(payload).not_to have_key(:metadata)
    ensure
      ActiveSupport::Notifications.unsubscribe(subscription)
    end
  end
end
