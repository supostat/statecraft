# frozen_string_literal: true

require "support/test_schema"

RSpec.describe "transition chains" do
  before do
    TestSchema.load!
    ActiveRecord::Base.connection.execute("DELETE FROM orders")
    ActiveRecord::Base.connection.execute("DELETE FROM order_transitions")
  end

  def define_chain_flow
    stub_const("CommitProbe", Class.new do
      def self.calls = (@calls ||= [])
    end)
    stub_const("OrderFlow", Class.new do
      include Statecraft::Machine

      state :pending, initial: true
      state :paid
      state :fulfilled

      event :pay, from: :pending, to: :paid
      event :fulfill, from: :paid, to: :fulfilled

      after_transition ->(record, _transition) { record.fire!(:fulfill) }, event: [:pay]
      after_commit ->(_record, transition) { CommitProbe.calls << transition.event }
    end)
    stub_const("Order", Class.new(ActiveRecord::Base) { self.table_name = "orders" })
    stub_const("OrderTransition", Class.new(ActiveRecord::Base) do
      self.table_name = "order_transitions"

      def readonly? = persisted?
    end)
    Order.state_machine(OrderFlow)
  end

  describe "a chain from after_transition" do
    it "writes one log row per transition" do
      define_chain_flow
      order = Order.create!

      order.fire!(:pay)

      expect(order.reload.state).to eq("fulfilled")
      expect(order.history.map(&:event)).to eq(%w[pay fulfill])
    end

    it "runs after_commit callbacks in inverted FIFO order: the nested one first" do
      define_chain_flow
      order = Order.create!

      order.fire!(:pay)

      expect(CommitProbe.calls).to eq(%i[fulfill pay])
    end
  end

  describe "the depth ceiling" do
    def define_ping_pong(chain_target)
      stub_const("PingPongFlow", Class.new do
        include Statecraft::Machine

        state :ping, initial: true
        state :pong

        event :hit, from: :ping, to: :pong
        event :back, from: :pong, to: :ping

        after_transition lambda { |record, transition|
          next if record.history.count >= PingPongFlow.chain_target

          record.fire!(transition.to == :pong ? :back : :hit)
        }
      end)
      PingPongFlow.define_singleton_method(:chain_target) { chain_target }
      stub_const("Order", Class.new(ActiveRecord::Base) { self.table_name = "orders" })
      stub_const("OrderTransition", Class.new(ActiveRecord::Base) do
        self.table_name = "order_transitions"

        def readonly? = persisted?
      end)
      Order.state_machine(PingPongFlow)
    end

    it "allows a chain of exactly 16 pipelines" do
      define_ping_pong(16)
      order = Order.create!(state: "ping")

      order.fire!(:hit)

      expect(order.history.count).to eq(16)
    end

    it "raises ChainDepthExceeded with the printed chain at depth 17" do
      define_ping_pong(50)
      order = Order.create!(state: "ping")

      expect { order.fire!(:hit) }.to raise_error(Statecraft::ChainDepthExceeded) do |error|
        expect(error.chain.length).to eq(17)
        expect(error.message).to include("ping -> pong (hit)")
        expect(error.message).to include("->")
      end
    end

    it "keeps the ceiling honest when identical loop frames repeat in the chain" do
      stub_const("LoopFlow", Class.new do
        include Statecraft::Machine

        state :spinning, initial: true

        event :spin, from: :spinning, to: :spinning

        after_transition lambda { |record, transition|
          next unless transition.metadata["spiral"]

          record.fire!(:spin, metadata: { "probe" => true })
          record.fire!(:spin, metadata: { "spiral" => true }) if record.history.count < 40
        }
      end)
      stub_const("Order", Class.new(ActiveRecord::Base) { self.table_name = "orders" })
      stub_const("OrderTransition", Class.new(ActiveRecord::Base) do
        self.table_name = "order_transitions"

        def readonly? = persisted?
      end)
      Order.state_machine(LoopFlow)
      order = Order.create!(state: "spinning")

      expect { order.fire!(:spin, metadata: { "spiral" => true }) }
        .to raise_error(Statecraft::ChainDepthExceeded)
    end
  end
end
