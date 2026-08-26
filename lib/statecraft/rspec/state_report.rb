# frozen_string_literal: true

module Statecraft
  module RSpec
    # The shared sentences of every failure message: where the record
    # stands, what the graph declares from there, what is reachable right
    # now, and which guards refused. Built strictly on the public
    # introspection surface — the matchers add words, never new answers.
    module StateReport
      module_function

      def current_state(record)
        record[record.class.statecraft_mounting.column]&.to_sym
      end

      def standing(record)
        "#{record.class.name} in state #{current_state(record).inspect}"
      end

      def machine(record)
        record.class.statecraft_mounting.machine_class
      end

      def event_declared?(record, event_name)
        machine(record).transitions_from(current_state(record))
                       .any? { |descriptor| descriptor[:events].include?(event_name) }
      end

      def declared_shape(machine_class, state)
        descriptors = machine_class.transitions_from(state)
        return "no edges are declared from #{state.inspect}" if descriptors.empty?

        rendered = descriptors.map do |descriptor|
          if descriptor[:events].empty?
            "to #{descriptor[:to].inspect} (direct)"
          else
            "to #{descriptor[:to].inspect} via #{descriptor[:events].inspect}"
          end
        end
        "declared from #{state.inspect}: #{rendered.join("; ")}"
      end

      def declared_shape_of(record)
        declared_shape(machine(record), current_state(record))
      end

      def reachable(record, metadata)
        transitions = record.available_transitions(metadata: metadata)
        state = current_state(record).inspect
        return "nothing is reachable from #{state} right now" if transitions.empty?

        rendered = transitions.map { |availability| "to #{availability.to.inspect} via #{availability.via.inspect}" }
        "reachable from #{state}: #{rendered.join("; ")}"
      end

      def refusal(record, event_name, metadata)
        refusals = record.refusals_for(event_name)
        if refusals.empty?
          "no record-layer guard refused — an input-reading guard: said no to metadata #{metadata.inspect}"
        else
          named = refusals.map { |entry| "#{entry.guard.inspect} (#{entry.layer})" }
          "refused by record-layer guards: #{named.join(", ")}"
        end
      end
    end
  end
end
