# frozen_string_literal: true

module Statecraft
  # The machine DSL and its compiler. A machine is declared in a dedicated
  # class (`include Statecraft::Machine`), collects states, edges, events and
  # callbacks, and compiles them into a deep-frozen graph on finalization.
  # Guard and callback symbols resolve to instance methods of the machine
  # class; callables are honored with a plain `call` and arity dispatch.
  module Machine
    # edge_guards / event_guards carry the FULL lists of all layers in
    # record-plain-input order — execution and the prediction run them as one
    # sequence. The parallel *_record_guards fields hold only the record
    # layer (read by the offering introspection); the *_input_guards fields
    # hold only the marked input layer (read by the question surface to
    # refuse a question asked without metadata).
    Edge = Struct.new(:from, :to, :lock, :edge_guards, :edge_record_guards, :edge_input_guards,
                      :event_names, :event_guards, :event_record_guards, :event_input_guards,
                      keyword_init: true)
    Callback = Struct.new(:handler, :from, :to, :event, keyword_init: true)
    CompiledGraph = Struct.new(
      :states, :initial_state, :edges, :events, :callbacks,
      keyword_init: true
    )

    CALLBACK_PHASES = %i[before_transition after_transition after_commit].freeze

    def self.included(machine_class)
      machine_class.extend(ClassMethods)
      machine_class.extend(Diagram)
    end

    # Invokes a guard or callback handler with the honest-call convention:
    # a Symbol resolves to a (possibly private) instance method of the machine,
    # a callable is called as-is with `self` untouched. Arity 1 receives the
    # record alone, everything else receives (record, payload) — the same
    # dispatch Active Record validators use.
    module Handlers
      def self.invoke(machine_instance, handler, record, payload)
        callable = resolve(machine_instance, handler)
        if unary?(callable)
          callable.call(record)
        else
          callable.call(record, payload)
        end
      end

      def self.resolve(machine_instance, handler)
        handler.is_a?(Symbol) ? machine_instance.method(handler) : handler
      end

      def self.unary?(callable)
        arity = callable.respond_to?(:arity) ? callable.arity : callable.method(:call).arity
        arity == 1
      end
    end

    # Class-level DSL collected declaratively and compiled by finalize!.
    # Names arrive as symbols or strings interchangeably (the ActiveRecord
    # idiom) and are normalized to symbols at the declaration line.
    module ClassMethods
      def state(name, initial: false)
        declared_states << { name: name.to_sym, initial: initial }
      end

      def transition(from:, to:, guard: nil, record_guard: nil, input_guard: nil, lock: false)
        declared_edges << {
          from: from.to_sym, to: to.to_sym,
          guards: Array(guard), record_guards: Array(record_guard),
          input_guards: Array(input_guard),
          lock: lock || current_event_lock,
          event: current_event_name
        }
      end

      def event(name, from: nil, to: nil, guard: nil, record_guard: nil, input_guard: nil, lock: false, &declarations)
        name = name.to_sym
        declared_event_names << name
        if declarations
          if from || to
            raise CompilationError, "event #{name.inspect} takes either inline from:/to: or a block, not both"
          end

          begin
            @statecraft_current_event = { name: name, lock: lock }
            yield
          ensure
            @statecraft_current_event = nil
          end
        else
          raise CompilationError, "event #{name.inspect} needs from:/to: or a block" if from.nil? || to.nil?

          @statecraft_current_event = { name: name, lock: false }
          begin
            transition(from: from, to: to, guard: guard, record_guard: record_guard,
                       input_guard: input_guard, lock: lock)
          ensure
            @statecraft_current_event = nil
          end
        end
      end

      CALLBACK_PHASES.each do |phase|
        define_method(phase) do |handler = nil, from: nil, to: nil, event: nil, &block|
          callback_handler = handler || block
          raise CompilationError, "#{phase} needs a method name or a callable" if callback_handler.nil?

          declared_callbacks[phase] << Callback.new(
            handler: callback_handler,
            from: from && Array(from).map(&:to_sym),
            to: to && Array(to).map(&:to_sym),
            event: event && Array(event).map(&:to_sym)
          )
        end
      end

      # Opt-in shape strictness: with strict! the compiler additionally
      # requires every declared state to be reachable from the initial one.
      # Off by default — the column is written by more than the gem, so an
      # unconnected state is legal unless the machine claims a closed graph.
      def strict!
        @statecraft_strict = true
      end

      def strict? = @statecraft_strict == true

      def states
        compiled_graph.states
      end

      def events
        compiled_graph.events.keys
      end

      # The graph's shape from one state: a frozen descriptor per outgoing
      # edge, `events` empty for a bare edge. Shape, not a prediction — no
      # guards are consulted, and a state outside the graph honestly owns no
      # edges. Class-level on purpose: the answer is a property of the graph,
      # never of a record.
      def transitions_from(state)
        normalized = state.to_sym
        compiled_graph.edges.filter_map do |(from, _to), edge|
          { to: edge.to, events: edge.event_names }.freeze if from == normalized
        end.freeze
      end

      def initial_state
        compiled_graph.initial_state
      end

      def compiled_graph
        finalize!
      end

      def finalized?
        !@statecraft_compiled_graph.nil?
      end

      # Compilation memoizes the graph and freezes the declaration lists, so a
      # reopened machine class fails loudly on any late state/transition/event
      # instead of silently ignoring it (callbacks already freeze in compile).
      def finalize!
        @statecraft_compiled_graph ||= Compiler.new(self).compile.tap { freeze_declarations }
      end

      def declared_states
        @statecraft_declared_states ||= []
      end

      def declared_edges
        @statecraft_declared_edges ||= []
      end

      def declared_event_names
        @statecraft_declared_event_names ||= []
      end

      def declared_callbacks
        @statecraft_declared_callbacks ||= CALLBACK_PHASES.to_h { |phase| [phase, []] }
      end

      private

      def freeze_declarations
        declared_states.freeze
        declared_edges.freeze
        declared_event_names.freeze
      end

      def current_event_name
        @statecraft_current_event && @statecraft_current_event[:name]
      end

      def current_event_lock
        @statecraft_current_event ? @statecraft_current_event[:lock] : false
      end
    end

    # Validates the declarations and produces the deep-frozen graph. All five
    # compilation errors live here, plus symbol resolution: every Symbol guard
    # or callback must exist as an instance method of the machine class at
    # finalization time (never checked at the declaration line, so a guard may
    # be declared above its def).
    class Compiler
      def initialize(machine_class)
        @machine_class = machine_class
      end

      def compile
        states = compile_states
        initial = compile_initial(states)
        edges = compile_edges(states)
        events = compile_events(edges)
        resolve_symbols(edges)
        assert_record_guards_unary(edges)
        assert_input_guards_binary(edges)
        assert_states_reachable(states, initial, edges) if machine_class.strict?
        CompiledGraph.new(
          states: states.freeze,
          initial_state: initial,
          edges: deep_freeze_edges(edges),
          events: freeze_events(events),
          callbacks: freeze_callbacks
        ).freeze
      end

      private

      attr_reader :machine_class

      def compile_states
        names = machine_class.declared_states.map { |declaration| declaration[:name] }
        duplicate = names.tally.find { |_name, count| count > 1 }
        raise CompilationError, "state #{duplicate.first.inspect} is declared twice" if duplicate

        names
      end

      def compile_initial(states)
        initials = machine_class.declared_states.select { |declaration| declaration[:initial] }.map { |d| d[:name] }
        raise CompilationError, "exactly one initial state is required, got none" if initials.empty?
        if initials.length > 1
          raise CompilationError, "exactly one initial state is required, got #{initials.join(", ")}"
        end

        initials.first.tap { |initial| assert_known_state(initial, states) }
      end

      def compile_edges(states)
        edges = {}
        machine_class.declared_edges.each do |declaration|
          assert_known_state(declaration[:from], states)
          assert_known_state(declaration[:to], states)
          pair = [declaration[:from], declaration[:to]]
          edge = edges[pair]
          if declaration[:event].nil?
            raise CompilationError, "duplicate edge #{pair_name(pair)}" if edge

            edges[pair] = build_edge(declaration)
          else
            edges[pair] = attach_event(edge, declaration, pair)
          end
        end
        edges
      end

      def build_edge(declaration)
        Edge.new(
          from: declaration[:from], to: declaration[:to], lock: declaration[:lock],
          edge_guards: declaration[:record_guards] + declaration[:guards] + declaration[:input_guards],
          edge_record_guards: declaration[:record_guards],
          edge_input_guards: declaration[:input_guards],
          event_names: [], event_guards: {}, event_record_guards: {}, event_input_guards: {}
        )
      end

      def attach_event(edge, declaration, pair)
        event_name = declaration[:event]
        edge ||= Edge.new(
          from: declaration[:from], to: declaration[:to], lock: false,
          edge_guards: [], edge_record_guards: [], edge_input_guards: [],
          event_names: [], event_guards: {}, event_record_guards: {}, event_input_guards: {}
        )
        if edge.event_names.include?(event_name)
          raise CompilationError, "event #{event_name.inspect} declares edge #{pair_name(pair)} twice"
        end

        edge.event_names << event_name
        edge.event_guards[event_name] = declaration[:record_guards] + declaration[:guards] +
                                        declaration[:input_guards]
        edge.event_record_guards[event_name] = declaration[:record_guards]
        edge.event_input_guards[event_name] = declaration[:input_guards]
        edge.lock ||= declaration[:lock]
        edge
      end

      def compile_events(edges)
        events = machine_class.declared_event_names.to_h { |name| [name, {}] }
        edges.each_value do |edge|
          edge.event_names.each do |event_name|
            branches = events[event_name]
            if branches.key?(edge.from)
              raise CompilationError,
                    "event #{event_name.inspect} has two edges from #{edge.from.inspect}: " \
                    "within one event, from must be unique"
            end
            branches[edge.from] = edge
          end
        end
        events.each do |name, branches|
          raise CompilationError, "event #{name.inspect} has no edges" if branches.empty?
        end
        events
      end

      def resolve_symbols(edges)
        symbol_handlers(edges).each do |symbol|
          next if machine_class.method_defined?(symbol) || machine_class.private_method_defined?(symbol)

          raise CompilationError,
                "guard or callback #{symbol.inspect} is not defined on #{machine_class.name || "the machine class"}"
        end
      end

      def symbol_handlers(edges)
        from_edges = edges.each_value.flat_map do |edge|
          edge.edge_guards + edge.event_guards.values.flatten
        end
        from_callbacks = machine_class.declared_callbacks.each_value.flat_map do |callbacks|
          callbacks.map(&:handler)
        end
        (from_edges + from_callbacks).grep(Symbol)
      end

      # A record guard promises to judge the record alone, and the promise is
      # held by shape: it must accept exactly one argument, so it physically
      # cannot read the input it claims not to need.
      def assert_record_guards_unary(edges)
        edges.each_value do |edge|
          record_guards = edge.edge_record_guards + edge.event_record_guards.values.flatten
          record_guards.each do |guard|
            arity = record_guard_arity(guard)
            next if arity == 1

            label = guard.is_a?(Symbol) ? guard.inspect : "the callable"
            raise CompilationError,
                  "record_guard #{label} must take exactly the record (arity 1), got arity #{arity}"
          end
        end
      end

      def record_guard_arity(guard)
        return machine_class.instance_method(guard).arity if guard.is_a?(Symbol)

        guard.respond_to?(:arity) ? guard.arity : guard.method(:call).arity
      end

      # An input guard promises that its answer is meaningless without the
      # input, and the promise is held by shape: it must accept exactly the
      # record and the metadata, so a question asked without metadata can be
      # refused instead of answered falsely.
      def assert_input_guards_binary(edges)
        edges.each_value do |edge|
          input_guards = edge.edge_input_guards + edge.event_input_guards.values.flatten
          input_guards.each do |guard|
            arity = record_guard_arity(guard)
            next if arity == 2

            label = guard.is_a?(Symbol) ? guard.inspect : "the callable"
            raise CompilationError,
                  "input_guard #{label} must take the record and the metadata (arity 2), got arity #{arity}"
          end
        end
      end

      # Strict reachability is a shape check, like transitions_from: edges
      # only, no guards. Dead ends stay legal — terminal states are the norm.
      def assert_states_reachable(states, initial, edges)
        unreachable = states - reachable_states(initial, edges)
        return if unreachable.empty?

        raise CompilationError,
              "strict!: unreachable from the initial #{initial.inspect}: " \
              "#{unreachable.map(&:inspect).join(", ")} — connect with edges or drop strict!"
      end

      def reachable_states(initial, edges)
        reached = [initial]
        queue = [initial]
        until queue.empty?
          from = queue.shift
          edges.each_key do |(edge_from, edge_to)|
            next if edge_from != from || reached.include?(edge_to)

            reached << edge_to
            queue << edge_to
          end
        end
        reached
      end

      def deep_freeze_edges(edges)
        edges.each_value do |edge|
          edge.edge_guards.freeze
          edge.edge_record_guards.freeze
          edge.edge_input_guards.freeze
          edge.event_names.freeze
          edge.event_guards.each_value(&:freeze)
          edge.event_guards.freeze
          edge.event_record_guards.each_value(&:freeze)
          edge.event_record_guards.freeze
          edge.event_input_guards.each_value(&:freeze)
          edge.event_input_guards.freeze
          edge.freeze
        end
        edges.freeze
      end

      def freeze_events(events)
        events.each_value(&:freeze)
        events.freeze
      end

      def freeze_callbacks
        callbacks = machine_class.declared_callbacks
        callbacks.each_value do |list|
          list.each do |callback|
            callback.from&.freeze
            callback.to&.freeze
            callback.event&.freeze
            callback.freeze
          end
          list.freeze
        end
        callbacks.freeze
      end

      def assert_known_state(name, states)
        return if states.include?(name)

        raise CompilationError, "unknown state #{name.inspect}: declare it with state #{name.inspect}"
      end

      def pair_name(pair)
        "#{pair.first} -> #{pair.last}"
      end
    end
  end
end
