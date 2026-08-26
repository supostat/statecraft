# frozen_string_literal: true

require "support/test_schema"
require "statecraft/rspec"

# The matchers' product is their failure messages, so half of these
# examples assert the TEXT a failing expectation prints — the state, the
# reachable edges, the refusing guard with its layer.
RSpec.describe "statecraft/rspec matchers" do
  before do
    TestSchema.load!
    ActiveRecord::Base.connection.execute("DELETE FROM orders")
    ActiveRecord::Base.connection.execute("DELETE FROM order_transitions")
    define_mounted_order
  end

  def define_mounted_order
    stub_const("MatcherFlow", Class.new do
      include Statecraft::Machine

      state :pending, initial: true
      state :paid
      state :cancelled
      state :archived

      event :pay, from: :pending, to: :paid, guard: ->(_record, metadata) { metadata["amount"].to_i.positive? }
      event :cancel, from: :pending, to: :cancelled, record_guard: :cancellable?
      event :void, from: :pending, to: :cancelled
      transition from: :pending, to: :archived
      transition from: :paid, to: :archived

      def cancellable?(record)
        record[:status] != "locked"
      end
    end)
    stub_const("Order", Class.new(ActiveRecord::Base) { self.table_name = "orders" })
    stub_const("OrderTransition", Class.new(ActiveRecord::Base) do
      self.table_name = "order_transitions"

      def readonly? = persisted?
    end)
    Order.state_machine(MatcherFlow)
  end

  def expect_failure(matching)
    expect { matching.call }.to raise_error(RSpec::Expectations::ExpectationNotMetError) do |error|
      yield error.message
    end
  end

  describe "allow_event" do
    it "passes with the metadata the guards need and refuses without" do
      order = Order.create!
      expect(order).to allow_event(:pay).with_metadata("amount" => 5)
      expect(order).not_to allow_event(:pay)
    end

    it "names the refusing record guard and its layer on failure" do
      order = Order.create!(status: "locked")
      expect_failure(-> { expect(order).to allow_event(:cancel) }) do |message|
        expect(message).to include("Order in state :pending")
        expect(message).to include(":cancellable? (event_record)")
      end
    end

    it "blames the input layer when no record guard refused" do
      order = Order.create!
      expect_failure(-> { expect(order).to allow_event(:pay).with_metadata("amount" => 0) }) do |message|
        expect(message).to include("input-reading guard")
        expect(message).to include({ "amount" => 0 }.inspect)
      end
    end

    it "shows the declared shape when the event has no branch from here" do
      order = Order.create!(state: "paid")
      expect_failure(-> { expect(order).to allow_event(:pay) }) do |message|
        expect(message).to include("event :pay is not declared from :paid")
        expect(message).to include("declared from :paid: to :archived (direct)")
      end
    end

    it "prints the passing metadata when negation fails" do
      order = Order.create!
      expect_failure(-> { expect(order).not_to allow_event(:pay).with_metadata("amount" => 5) }) do |message|
        expect(message).to include("not to allow event :pay")
        expect(message).to include({ "amount" => 5 }.inspect)
      end
    end
  end

  describe "refuse_event" do
    it "passes on a refusal and pins the refusing guard with because_of" do
      order = Order.create!(status: "locked")
      expect(order).to refuse_event(:cancel)
      expect(order).to refuse_event(:cancel).because_of(:cancellable?)
    end

    it "fails when the event is actually allowed" do
      order = Order.create!
      expect_failure(-> { expect(order).to refuse_event(:void) }) do |message|
        expect(message).to include("to refuse event :void")
        expect(message).to include("guards passed")
      end
    end

    it "is honest about because_of on an input-layer refusal" do
      order = Order.create!
      expect_failure(-> { expect(order).to refuse_event(:pay).because_of(:cancellable?) }) do |message|
        expect(message).to include("no record-layer guard refused")
        expect(message).to include("refusals_for names record-layer guards only")
      end
    end

    it "lists the actual refusers when because_of names the wrong guard" do
      order = Order.create!(status: "locked")
      expect_failure(-> { expect(order).to refuse_event(:cancel).because_of(:ghost_guard) }) do |message|
        expect(message).to include("to come from :ghost_guard")
        expect(message).to include("refusing record-layer guards were: :cancellable?")
      end
    end
  end

  describe "allow_transition_to" do
    it "answers the prediction with via, directly and metadata" do
      order = Order.create!
      expect(order).to allow_transition_to(:archived).directly
      expect(order).to allow_transition_to(:cancelled).via(:void)
      expect(order).to allow_transition_to(:paid).via(:pay).with_metadata("amount" => 5)
      expect(order).not_to allow_transition_to(:paid)
    end

    it "prints the reachability snapshot when the target is unreachable" do
      order = Order.create!
      expect_failure(-> { expect(order).to allow_transition_to(:paid) }) do |message|
        expect(message).to include("to reach :paid, but it cannot")
        expect(message).to include("reachable from :pending:")
        expect(message).to include("to :archived via [:direct]")
      end
    end

    it "shows the actual ways when via expects a refused event" do
      order = Order.create!(status: "locked")
      expect_failure(-> { expect(order).to allow_transition_to(:cancelled).via(:cancel) }) do |message|
        expect(message).to include("the way to :cancelled to include :cancel")
        expect(message).to include("reachable via [:void]")
      end
    end
  end

  describe "have_transitioned_to" do
    it "reads the log, not the current state" do
      order = Order.create!
      order.fire!(:pay, metadata: { "amount" => 5 })
      expect(order).to have_transitioned_to(:paid)
      expect(order).not_to have_transitioned_to(:cancelled)
    end

    it "prints what the log holds on failure" do
      order = Order.create!
      order.fire!(:void)
      expect_failure(-> { expect(order).to have_transitioned_to(:paid) }) do |message|
        expect(message).to include("the log holds transitions to: cancelled")
      end
    end

    it "says the log is empty when it is" do
      order = Order.create!
      expect_failure(-> { expect(order).to have_transitioned_to(:paid) }) do |message|
        expect(message).to include("the log is empty")
      end
    end
  end

  describe "have_edge and have_initial_state" do
    it "answers the shape without consulting guards" do
      expect(MatcherFlow).to have_edge(:pending, :cancelled).via(:cancel, :void)
      expect(MatcherFlow).to have_edge(:pending, :archived)
      expect(MatcherFlow).not_to have_edge(:archived, :pending)
      expect(MatcherFlow).to have_initial_state(:pending)
      expect(MatcherFlow).not_to have_initial_state(:paid)
    end

    it "shows the declared edges when the edge is missing" do
      expect_failure(-> { expect(MatcherFlow).to have_edge(:paid, :cancelled) }) do |message|
        expect(message).to include("to declare an edge :paid -> :cancelled")
        expect(message).to include("declared from :paid: to :archived (direct)")
      end
    end

    it "shows the actual events when via expects a missing one" do
      expect_failure(-> { expect(MatcherFlow).to have_edge(:pending, :paid).via(:ghost) }) do |message|
        expect(message).to include("to carry :ghost")
        expect(message).to include("events are [:pay]")
      end
    end

    it "prints the actual initial state on failure" do
      expect_failure(-> { expect(MatcherFlow).to have_initial_state(:paid) }) do |message|
        expect(message).to include("to be :paid, but it is :pending")
      end
    end
  end

  describe "transition" do
    it "asserts the state move and the appended log row in one expression" do
      order = Order.create!
      expect { order.fire!(:pay, metadata: { "amount" => 5 }) }
        .to transition(order).from(:pending).to(:paid)
                             .via_event(:pay).with_metadata("amount" => 5)
    end

    it "covers the direct bypass-free edge too" do
      order = Order.create!
      expect { order.transition_to!(:archived) }.to transition(order).to(:archived)
    end

    it "fails on a non-bang false and explains from the introspection" do
      order = Order.create!(status: "locked")
      failing = lambda do
        expect { order.fire(:cancel) }.to transition(order).to(:cancelled).via_event(:cancel)
      end
      expect_failure(failing) do |message|
        expect(message).to include("no transition happened: the record stayed in :pending")
        expect(message).to include("reachable from :pending:")
        expect(message).to include(":cancellable? (event_record)")
      end
    end

    it "names the mismatched event and metadata of the appended row" do
      order = Order.create!
      failing = lambda do
        expect { order.fire!(:void, metadata: { "reason" => "spec" }) }
          .to transition(order).to(:cancelled).via_event(:cancel).with_metadata("reason" => "other")
      end
      expect_failure(failing) do |message|
        expect(message).to include('written by event "void", not :cancel')
        written = { "reason" => "spec" }.inspect
        expected = { "reason" => "other" }.inspect
        expect(message).to include("metadata #{written}, not #{expected}")
      end
    end

    it "lets the exceptions of bang forms fly through" do
      order = Order.create!
      expect do
        expect { order.fire!(:pay) }.to transition(order).to(:paid)
      end.to raise_error(Statecraft::GuardFailed)
    end

    it "requires the .to target" do
      order = Order.create!
      expect do
        expect { order.fire!(:void) }.to transition(order)
      end.to raise_error(ArgumentError, /\.to target is required/)
    end

    it "supports negation for a block that moved nothing" do
      order = Order.create!
      expect { order.fire(:pay) }.not_to transition(order).to(:paid)
    end
  end
end
