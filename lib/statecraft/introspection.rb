# frozen_string_literal: true

module Statecraft
  # The record-facing questions: "would the guards pass if I fired this
  # transition with these metadata right now". Normalization and freeze are
  # identical to the pipeline's, so a guard that mutates metadata fails the
  # same way in a check as in a transition, and the answer never diverges from
  # what fire! would actually do. Every answer is a snapshot: CAS may still
  # reject the transition later.
  module Introspection
    Availability = Struct.new(:to, :via, keyword_init: true)
    Refusal = Struct.new(:event, :guard, :layer, keyword_init: true)

    def can_fire?(event_name, metadata: Metadata::OMITTED)
      graph = statecraft_graph
      branches = graph.events[event_name.to_sym]
      return false unless branches

      edge = branches[statecraft_current_state]
      return false unless edge

      normalized = statecraft_question_metadata(metadata, [[edge, event_name.to_sym]],
                                                question: "can_fire?(#{event_name.inspect})")
      statecraft_guards_pass?(edge, event_name.to_sym, normalized)
    end

    def available_events(metadata: Metadata::OMITTED)
      consulted = statecraft_graph.events.filter_map do |event_name, branches|
        edge = branches[statecraft_current_state]
        [edge, event_name] if edge
      end
      normalized = statecraft_question_metadata(metadata, consulted, question: "available_events")
      consulted.filter_map do |edge, event_name|
        event_name if statecraft_guards_pass?(edge, event_name, normalized)
      end
    end

    def available_transitions(metadata: Metadata::OMITTED)
      outgoing = statecraft_graph.edges.filter_map do |(from, _to), edge|
        edge if from == statecraft_current_state
      end
      consulted = outgoing.flat_map do |edge|
        pairs = edge.event_names.map { |event_name| [edge, event_name] }
        statecraft_direct_legal?(edge) ? pairs + [[edge, nil]] : pairs
      end
      normalized = statecraft_question_metadata(metadata, consulted, question: "available_transitions")
      outgoing.filter_map do |edge|
        via = statecraft_passable_via(edge, normalized)
        Availability.new(to: edge.to, via: via) unless via.empty?
      end
    end

    def transitioned_to?(state_name)
      history.where(to_state: state_name.to_s).exists?
    end

    # The offering: which events the graph AND this record allow from here —
    # the record layer alone, so an input-reading guard never hides the form
    # its input arrives through. A snapshot, like every question here.
    def offerable_events
      statecraft_graph.events.filter_map do |event_name, branches|
        edge = branches[statecraft_current_state]
        next unless edge

        event_name if statecraft_record_refusals(edge, event_name).empty?
      end
    end

    # The structured "why not": every record-layer guard refusing the event
    # right now. Guard handlers by name, no words — the words belong to the
    # presentation. An unknown event or a missing branch answers [].
    def refusals_for(event_name)
      branches = statecraft_graph.events[event_name.to_sym]
      return [].freeze unless branches

      edge = branches[statecraft_current_state]
      return [].freeze unless edge

      statecraft_record_refusals(edge, event_name.to_sym)
    end

    private

    # The single funnel for a question's metadata. Omitted with no input
    # guard on the consulted path degrades to an empty hash; omitted with
    # one raises MetadataRequired — the guard declared that its answer
    # without input would be a false "no". An explicit hash always passes.
    def statecraft_question_metadata(metadata, consulted_pairs, question:)
      return Metadata.normalize(metadata) unless metadata.equal?(Metadata::OMITTED)

      input_guards = consulted_pairs.flat_map { |edge, event_name| statecraft_input_guards(edge, event_name) }
      return Metadata.normalize({}) if input_guards.empty?

      raise MetadataRequired.new(record: self, question: question, guards: input_guards.uniq)
    end

    def statecraft_input_guards(edge, event_name)
      edge.edge_input_guards + (event_name ? edge.event_input_guards.fetch(event_name, []) : [])
    end

    def statecraft_record_refusals(edge, event_name)
      machine_instance = self.class.statecraft_mounting.machine_class.new
      layers = {
        edge_record: edge.edge_record_guards,
        event_record: edge.event_record_guards.fetch(event_name, [])
      }
      layers.flat_map do |layer, guards|
        guards.filter_map do |guard|
          next if Machine::Handlers.invoke(machine_instance, guard, self, nil)

          Refusal.new(event: event_name, guard: guard, layer: layer).freeze
        end
      end.freeze
    end

    def statecraft_passable_via(edge, normalized_metadata)
      via = edge.event_names.select do |event_name|
        statecraft_guards_pass?(edge, event_name, normalized_metadata)
      end
      direct = statecraft_direct_legal?(edge) && statecraft_guards_pass?(edge, nil, normalized_metadata)
      direct ? via + [:direct] : via
    end

    def statecraft_direct_legal?(edge)
      edge.event_guards.values.all?(&:empty?)
    end

    def statecraft_guards_pass?(edge, event_name, normalized_metadata)
      machine_instance = self.class.statecraft_mounting.machine_class.new
      guards = edge.edge_guards + (event_name ? edge.event_guards.fetch(event_name, []) : [])
      guards.all? do |guard|
        Machine::Handlers.invoke(machine_instance, guard, self, normalized_metadata)
      end
    end

    def statecraft_graph
      self.class.statecraft_mounting.machine_class.finalize!
    end

    def statecraft_current_state
      self[self.class.statecraft_mounting.column].to_s.to_sym
    end
  end
end
