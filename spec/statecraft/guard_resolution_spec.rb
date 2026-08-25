# frozen_string_literal: true

RSpec.describe "guard and callback resolution" do
  def record_stub(id)
    Struct.new(:id).new(id)
  end

  def machine_class(&definition)
    Class.new do
      include Statecraft::Machine

      class_eval(&definition)
    end
  end

  describe "symbol resolution at finalization" do
    it "resolves a public instance method of the machine" do
      flow = machine_class do
        state :a, initial: true
        state :b
        transition from: :a, to: :b, guard: :allowed?

        def allowed?(_record, _metadata) = true
      end
      expect { flow.finalize! }.not_to raise_error
    end

    it "resolves a private instance method: private guards are legal" do
      flow = machine_class do
        state :a, initial: true
        state :b
        transition from: :a, to: :b, guard: :allowed?

        private

        def allowed?(_record, _metadata) = true
      end
      expect { flow.finalize! }.not_to raise_error
    end

    it "checks at finalization, not at the declaration line" do
      flow = machine_class do
        state :a, initial: true
        state :b
        transition from: :a, to: :b, guard: :declared_below

        def declared_below(_record, _metadata) = true
      end
      expect { flow.finalize! }.not_to raise_error
    end

    it "rejects a missing guard symbol" do
      flow = machine_class do
        state :a, initial: true
        state :b
        transition from: :a, to: :b, guard: :ghost_guard
      end
      expect { flow.finalize! }.to raise_error(Statecraft::CompilationError, /:ghost_guard is not defined/)
    end

    it "rejects a missing callback symbol" do
      flow = machine_class do
        state :a, initial: true
        state :b
        transition from: :a, to: :b
        after_transition :ghost_callback
      end
      expect { flow.finalize! }.to raise_error(Statecraft::CompilationError, /:ghost_callback is not defined/)
    end

    it "accepts callables without any resolution" do
      flow = machine_class do
        state :a, initial: true
        state :b
        transition from: :a, to: :b, guard: ->(_record, _metadata) { true }
        before_transition ->(_record, _transition) { true }
      end
      expect { flow.finalize! }.not_to raise_error
    end
  end

  describe "the honest call convention" do
    it "calls a lambda with self untouched: the closure sees its definition site" do
      captured = []
      probe = ->(record, metadata) { captured << [record, metadata] }
      machine_instance = machine_class do
        state :a, initial: true
      end.new

      record = record_stub(1)
      Statecraft::Machine::Handlers.invoke(machine_instance, probe, record, { "k" => "v" })

      expect(captured).to eq([[record, { "k" => "v" }]])
    end

    it "calls a symbol on the machine instance, not on the record" do
      flow = machine_class do
        state :a, initial: true

        def seen
          @seen ||= []
        end

        private

        def note_call(record, metadata)
          seen << [record, metadata]
          true
        end
      end
      machine_instance = flow.new
      record = record_stub(2)

      Statecraft::Machine::Handlers.invoke(machine_instance, :note_call, record, {})

      expect(machine_instance.seen).to eq([[record, {}]])
    end
  end

  describe "arity dispatch" do
    it "passes only the record to an arity-1 lambda" do
      captured = nil
      unary = ->(record) { captured = record }
      machine_instance = machine_class { state :a, initial: true }.new
      record = record_stub(3)

      Statecraft::Machine::Handlers.invoke(machine_instance, unary, record, { "ignored" => true })

      expect(captured).to eq(record)
    end

    it "passes record and payload to an arity-2 method" do
      flow = machine_class do
        state :a, initial: true

        def captured
          @captured ||= []
        end

        def binary(record, metadata)
          captured << [record, metadata]
        end
      end
      machine_instance = flow.new
      record = record_stub(4)

      Statecraft::Machine::Handlers.invoke(machine_instance, :binary, record, { "m" => 1 })

      expect(machine_instance.captured).to eq([[record, { "m" => 1 }]])
    end

    it "passes only the record to an arity-1 method" do
      flow = machine_class do
        state :a, initial: true

        def captured
          @captured ||= []
        end

        def unary(record)
          captured << record
        end
      end
      machine_instance = flow.new
      record = record_stub(5)

      Statecraft::Machine::Handlers.invoke(machine_instance, :unary, record, { "m" => 1 })

      expect(machine_instance.captured).to eq([record])
    end

    it "passes both arguments to a splat-arity callable" do
      captured = nil
      variadic = ->(*handler_arguments) { captured = handler_arguments }
      machine_instance = machine_class { state :a, initial: true }.new
      record = record_stub(6)

      Statecraft::Machine::Handlers.invoke(machine_instance, variadic, record, { "m" => 2 })

      expect(captured).to eq([record, { "m" => 2 }])
    end

    it "dispatches a plain callable object by its call arity" do
      guard_class = Class.new do
        attr_reader :captured

        def call(record, metadata)
          @captured = [record, metadata]
        end
      end
      guard = guard_class.new
      machine_instance = machine_class { state :a, initial: true }.new
      record = record_stub(7)

      Statecraft::Machine::Handlers.invoke(machine_instance, guard, record, { "m" => 3 })

      expect(guard.captured).to eq([record, { "m" => 3 }])
    end

    it "passes only the record to a unary callable object" do
      guard_class = Class.new do
        attr_reader :captured

        def call(record)
          @captured = record
        end
      end
      guard = guard_class.new
      machine_instance = machine_class { state :a, initial: true }.new
      record = record_stub(8)

      Statecraft::Machine::Handlers.invoke(machine_instance, guard, record, { "m" => 4 })

      expect(guard.captured).to eq(record)
    end
  end

  describe "the stateless machine instance" do
    it "instantiates without arguments and carries no per-transition state" do
      flow = machine_class { state :a, initial: true }
      expect(flow.new).not_to equal(flow.new)
    end
  end

  describe "record guard resolution" do
    it "resolves a private record guard like any other guard symbol" do
      flow = machine_class do
        state :a, initial: true
        state :b
        event :go, from: :a, to: :b, record_guard: :kind_ok?

        private

        def kind_ok?(_record) = true
      end

      expect { flow.finalize! }.not_to raise_error
    end

    it "rejects a missing record guard symbol through the same existence check" do
      flow = machine_class do
        state :a, initial: true
        state :b
        event :go, from: :a, to: :b, record_guard: :ghost_kind?
      end

      expect { flow.finalize! }.to raise_error(Statecraft::CompilationError, /:ghost_kind\? is not defined/)
    end

    it "holds the unary contract for a private record guard too" do
      flow = machine_class do
        state :a, initial: true
        state :b
        event :go, from: :a, to: :b, record_guard: :kind_ok?

        private

        def kind_ok?(_record, _metadata) = true
      end

      expect { flow.finalize! }
        .to raise_error(Statecraft::CompilationError, /record_guard :kind_ok\? must take exactly the record/)
    end
  end
end
