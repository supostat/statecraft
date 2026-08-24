# frozen_string_literal: true

module Statecraft
  class Pipeline
    # Resolves the requested edge from the compiled graph and raises
    # InvalidTransition with a diagnosis that names what actually failed:
    # an undeclared edge, a bypass-policy refusal, an unknown event, or an
    # event with no branch from the current state.
    module EdgeResolution
      private

      def resolve_direct_edge(current, to_state, bypass_events)
        edge = graph.edges[[current, to_state]]
        raise_invalid_transition(current, to_state) if edge.nil?
        guarding_events = edge.event_names.select { |name| edge.event_guards[name].any? }
        if guarding_events.any? && !bypass_events
          raise InvalidTransition.new(
            record: record, from: current, requested: to_state,
            allowed: allowed_targets(current),
            message: "direct transition #{current} -> #{to_state} is guarded by " \
                     "event#{"s" if guarding_events.length > 1} #{guarding_events.join(", ")}; " \
                     "call fire!(:#{guarding_events.first}) or pass bypass_events: true"
          )
        end
        edge
      end

      def resolve_event_edge(current, event_name)
        branches = graph.events[event_name]
        raise_unknown_event(current, event_name) if branches.nil?
        edge = branches[current]
        raise_event_without_branch(current, event_name, branches) if edge.nil?
        edge
      end

      def raise_unknown_event(current, event_name)
        known_events = graph.events.keys
        raise InvalidTransition.new(
          record: record, from: current, requested: event_name,
          allowed: allowed_targets(current),
          message: "unknown event #{event_name.inspect} for #{configuration.machine_class.name}; " \
                   "events: #{known_events.empty? ? "none" : known_events.map(&:inspect).join(", ")}"
        )
      end

      def raise_event_without_branch(current, event_name, branches)
        declared_branches = branches.map { |from, edge| "#{from} -> #{edge.to}" }.join(", ")
        raise InvalidTransition.new(
          record: record, from: current, requested: event_name,
          allowed: allowed_targets(current),
          message: "event #{event_name.inspect} has no branch from #{current} for " \
                   "#{record.class.name}; branches: #{declared_branches}"
        )
      end

      def raise_invalid_transition(current, requested)
        raise InvalidTransition.new(
          record: record, from: current, requested: requested,
          allowed: allowed_targets(current)
        )
      end

      def allowed_targets(current)
        graph.edges.keys.select { |from, _to| from == current }.map(&:last)
      end
    end
  end
end
