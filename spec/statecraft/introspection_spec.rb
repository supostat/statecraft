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

  describe "transitions_from" do
    it "answers the graph's shape from a state as frozen {to, events} descriptors" do
      descriptors = OrderFlow.transitions_from(:pending)
      expected_shape = [
        { to: :paid, events: [:pay] },
        { to: :cancelled, events: [] }
      ]
      expect(descriptors).to eq(expected_shape)
      expect(descriptors).to be_frozen
      expect(descriptors).to all(be_frozen)
    end

    it "returns every event name of a multi-named edge in declaration order" do
      flow = Class.new do
        include Statecraft::Machine

        state :pending, initial: true
        state :cancelled

        event :cancel, from: :pending, to: :cancelled, guard: ->(_record, _metadata) { true }
        event :admin_override, from: :pending, to: :cancelled
      end
      expect(flow.transitions_from(:pending)).to eq([{ to: :cancelled, events: %i[cancel admin_override] }])
    end

    it "accepts a string state name per the DSL idiom" do
      expect(OrderFlow.transitions_from("pending")).to eq(OrderFlow.transitions_from(:pending))
    end

    it "answers [] for a state outside the graph: no edges is the honest shape" do
      expect(OrderFlow.transitions_from(:ghost)).to eq([])
    end

    it "consults no guards: the shape ignores metadata entirely" do
      order = Order.create!
      expect(order.available_transitions(metadata: { amount: 0 }).map(&:to)).to eq([:cancelled])
      expect(OrderFlow.transitions_from(:pending).map { |descriptor| descriptor[:to] }).to eq(%i[paid cancelled])
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

  describe "the record-layer offering" do
    def define_offering_order
      stub_const("OfferFlow", Class.new do
        include Statecraft::Machine

        state :pending, initial: true
        state :paid
        state :cancelled
        state :archived

        event :pay,
              from: :pending, to: :paid,
              record_guard: :payable_kind?,
              guard: ->(_record, metadata) { metadata["amount"].to_i.positive? }
        event :cancel, from: :pending, to: :cancelled, record_guard: :regular_kind?
        transition from: :pending, to: :archived, record_guard: :never_open?
        event :archive, from: :pending, to: :archived

        def payable_kind?(record) = record.status != "blocked"
        def regular_kind?(record) = record.status != "credit"
        def never_open?(_record) = false
      end)
      stub_const("Order", Class.new(ActiveRecord::Base) { self.table_name = "orders" })
      Order.state_machine(OfferFlow, log: OrderTransition)
    end

    before { define_offering_order }

    describe "offerable_events" do
      it "offers events whose record layer passes, ignoring input guards" do
        order = Order.create!
        expect(order.offerable_events).to eq(%i[pay cancel])
      end

      it "drops an event whose record guard refuses this record" do
        credit = Order.create!(status: "credit")
        expect(credit.offerable_events).to eq([:pay])
      end

      it "consults the edge record layer for events riding that edge" do
        order = Order.create!
        expect(order.offerable_events).not_to include(:archive)
      end

      it "answers [] for a state outside the graph" do
        order = Order.create!
        order.update_column(:state, "limbo")
        expect(order.reload.offerable_events).to eq([])
      end

      it "is a snapshot of the record as it stands right now" do
        order = Order.create!
        order.status = "credit"
        expect(order.offerable_events).to eq([:pay])
        order.status = "draft"
        expect(order.offerable_events).to eq(%i[pay cancel])
      end
    end

    describe "refusals_for" do
      it "names the refusing event record guard" do
        credit = Order.create!(status: "credit")
        refusals = credit.refusals_for(:cancel)

        expect(refusals.length).to eq(1)
        expect(refusals.first.event).to eq(:cancel)
        expect(refusals.first.guard).to eq(:regular_kind?)
        expect(refusals.first.layer).to eq(:event_record)
        expect(refusals.first).to be_frozen
      end

      it "names the refusing edge record guard with its own layer" do
        order = Order.create!
        refusals = order.refusals_for(:archive)

        expect(refusals.map(&:guard)).to eq([:never_open?])
        expect(refusals.map(&:layer)).to eq([:edge_record])
      end

      it "answers [] when the record layer passes" do
        expect(Order.create!.refusals_for(:cancel)).to eq([])
      end

      it "answers [] for an unknown event and for an event without a branch" do
        order = Order.create!(state: "paid")
        expect(order.refusals_for(:ghost)).to eq([])
        expect(order.refusals_for(:cancel)).to eq([])
      end
    end
  end

  describe "input guards on the question surface" do
    def define_input_guarded_order
      stub_const("InputFlow", Class.new do
        include Statecraft::Machine

        state :pending, initial: true
        state :paid
        state :cancelled

        event :pay, from: :pending, to: :paid, input_guard: :amount_positive?
        event :void, from: :pending, to: :cancelled
        transition from: :cancelled, to: :pending, input_guard: :amount_positive?

        def amount_positive?(_record, metadata)
          metadata["amount"].to_i.positive?
        end
      end)
      stub_const("Order", Class.new(ActiveRecord::Base) { self.table_name = "orders" })
      stub_const("OrderTransition", Class.new(ActiveRecord::Base) do
        self.table_name = "order_transitions"

        def readonly? = persisted?
      end)
      Order.state_machine(InputFlow)
    end

    it "refuses a bare can_fire? naming the guard and the recipe" do
      define_input_guarded_order
      order = Order.create!
      expect { order.can_fire?(:pay) }.to raise_error(Statecraft::MetadataRequired) do |error|
        expect(error.guards).to eq([:amount_positive?])
        expect(error.message).to include("can_fire?(:pay) on Order consults input guards :amount_positive?")
        expect(error.message).to include("an explicit metadata: {} means the input is empty")
      end
    end

    it "accepts an explicit empty hash as 'my input is empty'" do
      define_input_guarded_order
      order = Order.create!
      expect(order.can_fire?(:pay, metadata: {})).to be(false)
      expect(order.can_fire?(:pay, metadata: { amount: 5 })).to be(true)
    end

    it "answers false about an unknown event before demanding metadata" do
      define_input_guarded_order
      expect(Order.create!.can_fire?(:ghost)).to be(false)
    end

    it "leaves a bare question about an unmarked path untouched" do
      define_input_guarded_order
      order = Order.create!
      expect(order.can_fire?(:void)).to be(true)
    end

    it "refuses bare enumerations that would consult the marked guard" do
      define_input_guarded_order
      order = Order.create!
      expect { order.available_events }.to raise_error(Statecraft::MetadataRequired)
      expect { order.available_transitions }.to raise_error(Statecraft::MetadataRequired)
      expect(order.available_events(metadata: {})).to eq([:void])
    end

    it "does not demand metadata once no marked guard stands on the path" do
      define_input_guarded_order
      order = Order.create!(state: "paid")
      expect(order.available_events).to eq([])
      expect(order.available_transitions).to eq([])
    end

    it "counts an edge-level input guard on the direct path too" do
      define_input_guarded_order
      order = Order.create!(state: "cancelled")
      expect { order.available_transitions }.to raise_error(Statecraft::MetadataRequired)
      expect(order.available_transitions(metadata: { amount: 5 }).map(&:to)).to eq([:pending])
    end

    it "keeps execution unchanged: a bare call is an empty input, refused by the guard" do
      define_input_guarded_order
      order = Order.create!
      expect { order.fire!(:pay) }.to raise_error(Statecraft::GuardFailed, /amount_positive?/)
      expect(order.fire!(:pay, metadata: { amount: 5 })).to be_a(OrderTransition)
    end
  end
end
