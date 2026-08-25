# frozen_string_literal: true

RSpec.describe "machine compilation" do
  def machine_class(&definition)
    Class.new do
      include Statecraft::Machine

      class_eval(&definition)
    end
  end

  describe "name normalization" do
    it "accepts strings for states, transitions, events and callback filters" do
      flow = machine_class do
        state "draft", initial: true
        state "sent"
        event "send_off", from: "draft", to: "sent"
        after_transition ->(_record, _transition) {}, from: "draft", to: ["sent"], event: "send_off"
      end

      expect(flow.states).to eq(%i[draft sent])
      expect(flow.initial_state).to eq(:draft)
      expect(flow.events).to eq([:send_off])
      expect(flow.compiled_graph.edges[%i[draft sent]]).not_to be_nil

      callback = flow.compiled_graph.callbacks[:after_transition].first
      expect(callback.from).to eq([:draft])
      expect(callback.to).to eq([:sent])
      expect(callback.event).to eq([:send_off])
    end
  end

  describe "finalization freezes the DSL" do
    it "raises FrozenError on state, transition and event after finalize!" do
      flow = machine_class do
        state :a, initial: true
        state :b
        transition from: :a, to: :b
      end
      flow.finalize!

      expect { flow.state :late }.to raise_error(FrozenError)
      expect { flow.transition from: :a, to: :b }.to raise_error(FrozenError)
      expect { flow.event :late_event, from: :a, to: :b }.to raise_error(FrozenError)
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

    it "collects several event names on one edge, each with its own guards" do
      flow = machine_class do
        state :a, initial: true
        state :b
        event :go, from: :a, to: :b, guard: ->(_record, _metadata) { true }
        event :force_go, from: :a, to: :b
      end
      edge = flow.compiled_graph.edges[%i[a b]]
      expect(edge.event_names).to eq(%i[go force_go])
      expect(edge.event_guards.fetch(:go).length).to eq(1)
      expect(edge.event_guards.fetch(:force_go)).to eq([])
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

  describe "guard layers" do
    it "compiles event guards as one record-first list plus a parallel record view" do
      flow = machine_class do
        state :a, initial: true
        state :b
        event :go, from: :a, to: :b, record_guard: :kind_ok?, guard: :input_ok?

        def kind_ok?(_record) = true
        def input_ok?(_record, _metadata) = true
      end

      edge = flow.compiled_graph.edges[%i[a b]]
      expect(edge.event_guards[:go]).to eq(%i[kind_ok? input_ok?])
      expect(edge.event_record_guards[:go]).to eq(%i[kind_ok?])
      expect(edge.edge_guards).to eq([])
    end

    it "compiles edge guards the same way on a bare transition" do
      flow = machine_class do
        state :a, initial: true
        state :b
        transition from: :a, to: :b, record_guard: :kind_ok?, guard: :input_ok?

        def kind_ok?(_record) = true
        def input_ok?(_record, _metadata) = true
      end

      edge = flow.compiled_graph.edges[%i[a b]]
      expect(edge.edge_guards).to eq(%i[kind_ok? input_ok?])
      expect(edge.edge_record_guards).to eq(%i[kind_ok?])
    end

    it "keeps event record guards inside the event layer, so bypass skips them with it" do
      flow = machine_class do
        state :a, initial: true
        state :b
        event :go, from: :a, to: :b, record_guard: :kind_ok?

        def kind_ok?(_record) = true
      end

      edge = flow.compiled_graph.edges[%i[a b]]
      expect(edge.edge_guards).to eq([])
      expect(edge.event_guards[:go]).to eq(%i[kind_ok?])
    end

    it "rejects a symbol record guard that wants metadata" do
      flow = machine_class do
        state :a, initial: true
        state :b
        event :go, from: :a, to: :b, record_guard: :greedy?

        def greedy?(_record, _metadata) = true
      end

      expect { flow.finalize! }
        .to raise_error(Statecraft::CompilationError, /record_guard :greedy\? must take exactly the record/)
    end

    it "rejects a callable record guard of arity 2" do
      flow = machine_class do
        state :a, initial: true
        state :b
        transition from: :a, to: :b, record_guard: ->(_record, _metadata) { true }
      end

      expect { flow.finalize! }
        .to raise_error(Statecraft::CompilationError, /record_guard the callable must take exactly the record/)
    end

    it "freezes the record-layer collections with the rest of the edge" do
      flow = machine_class do
        state :a, initial: true
        state :b
        event :go, from: :a, to: :b, record_guard: :kind_ok?

        def kind_ok?(_record) = true
      end

      edge = flow.compiled_graph.edges[%i[a b]]
      expect(edge.edge_record_guards).to be_frozen
      expect(edge.event_record_guards).to be_frozen
      expect(edge.event_record_guards[:go]).to be_frozen
    end
  end
end
