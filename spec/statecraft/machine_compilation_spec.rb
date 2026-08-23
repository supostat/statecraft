# frozen_string_literal: true

RSpec.describe "machine compilation" do
  def machine_class(&definition)
    Class.new do
      include Statecraft::Machine

      class_eval(&definition)
    end
  end

  describe "the DSL" do
    let(:flow) do
      machine_class do
        state :pending, initial: true
        state :paid
        state :failed
        state :refunded
        state :archived

        transition from: :paid, to: :archived

        event :pay, from: :pending, to: :paid, guard: ->(_record, _metadata) { true }
        event :fail_payment, from: :pending, to: :failed

        event :refund do
          transition from: :paid, to: :refunded, guard: ->(_record) { true }
          transition from: :failed, to: :refunded
        end
      end
    end

    it "lists states in declaration order" do
      expect(flow.states).to eq(%i[pending paid failed refunded archived])
    end

    it "knows the single initial state" do
      expect(flow.initial_state).to eq(:pending)
    end

    it "lists declared events" do
      expect(flow.events).to contain_exactly(:pay, :fail_payment, :refund)
    end

    it "compiles an event as a partial function from -> edge" do
      branches = flow.compiled_graph.events[:refund]
      expect(branches.keys).to contain_exactly(:paid, :failed)
      expect(branches[:paid].to).to eq(:refunded)
    end

    it "keeps a bare edge without event names" do
      edge = flow.compiled_graph.edges[%i[paid archived]]
      expect(edge.event_names).to be_empty
    end

    it "records event guards on the edge under the event name" do
      edge = flow.compiled_graph.edges[%i[pending paid]]
      expect(edge.event_guards.fetch(:pay).length).to eq(1)
      expect(edge.edge_guards).to be_empty
    end
  end

  describe "lock propagation" do
    it "applies event-level lock to every edge of the event" do
      flow = machine_class do
        state :a, initial: true
        state :b
        state :c
        event :go, lock: true do
          transition from: :a, to: :b
          transition from: :b, to: :c
        end
      end
      expect(flow.compiled_graph.edges[%i[a b]].lock).to be(true)
      expect(flow.compiled_graph.edges[%i[b c]].lock).to be(true)
    end

    it "honors edge-level lock on a bare transition" do
      flow = machine_class do
        state :a, initial: true
        state :b
        transition from: :a, to: :b, lock: true
      end
      expect(flow.compiled_graph.edges[%i[a b]].lock).to be(true)
    end
  end

  describe "an event attaching to an existing bare edge" do
    it "adds the event name and keeps the edge guard separate" do
      flow = machine_class do
        state :a, initial: true
        state :b
        transition from: :a, to: :b, guard: ->(_record, _metadata) { true }
        event :go, from: :a, to: :b, guard: ->(_record, _metadata) { true }
      end
      edge = flow.compiled_graph.edges[%i[a b]]
      expect(edge.event_names).to eq([:go])
      expect(edge.edge_guards.length).to eq(1)
      expect(edge.event_guards.fetch(:go).length).to eq(1)
    end
  end

  describe "compilation errors" do
    it "rejects an unknown state in from" do
      flow = machine_class do
        state :a, initial: true
        transition from: :ghost, to: :a
      end
      expect { flow.finalize! }.to raise_error(Statecraft::CompilationError, /unknown state :ghost/)
    end

    it "rejects an unknown state in to" do
      flow = machine_class do
        state :a, initial: true
        transition from: :a, to: :ghost
      end
      expect { flow.finalize! }.to raise_error(Statecraft::CompilationError, /unknown state :ghost/)
    end

    it "rejects two initial states" do
      flow = machine_class do
        state :a, initial: true
        state :b, initial: true
      end
      expect { flow.finalize! }.to raise_error(Statecraft::CompilationError, /exactly one initial/)
    end

    it "rejects a machine with no initial state" do
      flow = machine_class do
        state :a
        state :b
        transition from: :a, to: :b
      end
      expect { flow.finalize! }.to raise_error(Statecraft::CompilationError, /exactly one initial/)
    end

    it "rejects a duplicate bare edge" do
      flow = machine_class do
        state :a, initial: true
        state :b
        transition from: :a, to: :b
        transition from: :a, to: :b
      end
      expect { flow.finalize! }.to raise_error(Statecraft::CompilationError, /duplicate edge a -> b/)
    end

    it "rejects duplicate from within one event" do
      flow = machine_class do
        state :a, initial: true
        state :b
        state :c
        event :go do
          transition from: :a, to: :b
          transition from: :a, to: :c
        end
      end
      expect { flow.finalize! }.to raise_error(Statecraft::CompilationError, /two edges from :a/)
    end

    it "rejects an event with zero edges" do
      flow = machine_class do
        state :a, initial: true
        event :hollow do # rubocop:disable Lint/EmptyBlock
        end
      end
      expect { flow.finalize! }.to raise_error(Statecraft::CompilationError, /event :hollow has no edges/)
    end

    it "rejects an event mixing inline pair and a block" do
      expect do
        machine_class do
          state :a, initial: true
          state :b
          event :go, from: :a, to: :b do
            transition from: :a, to: :b
          end
        end
      end.to raise_error(Statecraft::CompilationError, /either inline from/)
    end

    it "allows an unreachable declared state silently" do
      flow = machine_class do
        state :a, initial: true
        state :b
        state :legacy
        transition from: :a, to: :b
      end
      expect(flow.states).to include(:legacy)
    end

    it "allows a dead-end state silently" do
      flow = machine_class do
        state :a, initial: true
        state :done
        transition from: :a, to: :done
      end
      expect(flow.states).to include(:done)
    end
  end

  describe "deep freeze" do
    let(:flow) do
      machine_class do
        state :a, initial: true
        state :b
        event :go, from: :a, to: :b
      end
    end

    it "freezes the graph, its collections and edges" do
      graph = flow.compiled_graph
      expect(graph).to be_frozen
      expect(graph.states).to be_frozen
      expect(graph.edges).to be_frozen
      expect(graph.events).to be_frozen
      graph.edges.each_value do |edge|
        expect(edge).to be_frozen
        expect(edge.event_names).to be_frozen
        expect(edge.event_guards).to be_frozen
      end
    end

    it "is idempotent: finalize! returns the same graph" do
      expect(flow.finalize!).to equal(flow.finalize!)
    end
  end
end
