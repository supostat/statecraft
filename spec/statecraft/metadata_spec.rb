# frozen_string_literal: true

require "support/test_schema"

RSpec.describe "metadata normalization and freeze" do
  before do
    TestSchema.load!
    ActiveRecord::Base.connection.execute("DELETE FROM orders")
    ActiveRecord::Base.connection.execute("DELETE FROM order_transitions")
  end

  def define_mounted_order(guard: nil)
    captured_guard = guard
    stub_const("OrderFlow", Class.new do
      include Statecraft::Machine

      state :pending, initial: true
      state :paid
      event :pay, from: :pending, to: :paid, guard: captured_guard
    end)
    stub_const("Order", Class.new(ActiveRecord::Base) { self.table_name = "orders" })
    stub_const("OrderTransition", Class.new(ActiveRecord::Base) do
      self.table_name = "order_transitions"

      def readonly? = persisted?
    end)
    Order.state_machine(OrderFlow)
  end

  describe "the JSON round-trip" do
    it "stringifies symbol keys and values before the guards" do
      seen = nil
      define_mounted_order(guard: ->(_record, metadata) { seen = metadata })
      Order.create!.fire!(:pay, metadata: { reason: :fraud, "kept" => 1 })

      expect(seen).to eq({ "reason" => "fraud", "kept" => 1 })
    end

    it "turns times into ISO-8601 strings" do
      seen = nil
      define_mounted_order(guard: ->(_record, metadata) { seen = metadata })
      moment = Time.utc(2026, 8, 23, 12, 0, 0)
      Order.create!.fire!(:pay, metadata: { at: moment })

      expect(seen["at"]).to eq("2026-08-23T12:00:00Z")
    end

    it "stores exactly what the guard saw" do
      seen = nil
      define_mounted_order(guard: ->(_record, metadata) { seen = metadata })
      log_record = Order.create!.fire!(:pay, metadata: { reason: :fraud })

      expect(log_record.metadata).to eq(seen)
    end

    it "normalizes nested structures" do
      seen = nil
      define_mounted_order(guard: ->(_record, metadata) { seen = metadata })
      Order.create!.fire!(:pay, metadata: { items: [{ sku: :a }, { sku: :b }] })

      expect(seen).to eq({ "items" => [{ "sku" => "a" }, { "sku" => "b" }] })
    end
  end

  describe "instant failure on unserializable input" do
    it "rejects a Proc before touching the database" do
      define_mounted_order
      order = Order.create!
      expect { order.fire!(:pay, metadata: { p: proc { 1 } }) }
        .to raise_error(ArgumentError, /not JSON-serializable/)
      expect(OrderTransition.count).to eq(0)
      expect(order.reload.state).to eq("pending")
    end

    it "rejects an ActiveRecord object as a value" do
      define_mounted_order
      order = Order.create!
      expect { order.fire!(:pay, metadata: { record: order }) }
        .to raise_error(ArgumentError, /not JSON-serializable/)
    end

    it "rejects a non-stringlike key" do
      define_mounted_order
      order = Order.create!
      expect { order.fire!(:pay, metadata: { [1, 2] => "x" }) }
        .to raise_error(ArgumentError, /not a JSON object key/)
    end

    it "rejects NaN and Infinity before touching the database" do
      define_mounted_order
      order = Order.create!
      [Float::NAN, Float::INFINITY, -Float::INFINITY].each do |non_finite|
        expect { order.fire!(:pay, metadata: { ratio: non_finite }) }
          .to raise_error(ArgumentError, /no NaN or Infinity/)
      end
      expect(OrderTransition.count).to eq(0)
    end

    it "rejects a non-finite float nested inside arrays and hashes" do
      define_mounted_order
      order = Order.create!
      expect { order.fire!(:pay, metadata: { readings: [{ value: Float::NAN }] }) }
        .to raise_error(ArgumentError, /no NaN or Infinity/)
    end
  end

  describe "deep freeze: write-once starts at normalization" do
    it "raises FrozenError when a guard mutates metadata during a transition" do
      define_mounted_order(guard: ->(_record, metadata) { metadata["sneak"] = 1 })
      order = Order.create!
      expect { order.fire!(:pay, metadata: { a: 1 }) }.to raise_error(FrozenError)
      expect(OrderTransition.count).to eq(0)
    end

    it "freezes nested structures too" do
      define_mounted_order(guard: ->(_record, metadata) { metadata["items"] << "sneak" })
      order = Order.create!
      expect { order.fire!(:pay, metadata: { items: ["a"] }) }.to raise_error(FrozenError)
    end

    it "hands every phase the same frozen object" do
      captured = []
      stub_const("ProbeFlow", Class.new do
        include Statecraft::Machine

        state :pending, initial: true
        state :paid
        event :pay, from: :pending, to: :paid, guard: lambda { |_r, metadata|
          captured << metadata
          true
        }
        before_transition ->(_r, transition) { captured << transition.metadata }
        after_transition ->(_r, transition) { captured << transition.metadata }
      end)
      stub_const("Order", Class.new(ActiveRecord::Base) { self.table_name = "orders" })
      stub_const("OrderTransition", Class.new(ActiveRecord::Base) do
        self.table_name = "order_transitions"

        def readonly? = persisted?
      end)
      Order.state_machine(ProbeFlow)
      Order.create!.fire!(:pay, metadata: { a: 1 })

      expect(captured.length).to eq(3)
      expect(captured.uniq(&:object_id).length).to eq(1)
      expect(captured.first).to be_frozen
    end
  end
end
