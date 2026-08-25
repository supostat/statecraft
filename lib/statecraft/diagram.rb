# frozen_string_literal: true

module Statecraft
  # Renders the compiled graph as Mermaid stateDiagram-v2 text: the states,
  # the initial marker and event-labeled edges in declaration order. The
  # shape only — like transitions_from, no guards are consulted or rendered.
  module Diagram
    def to_mermaid
      graph = finalize!
      lines = ["stateDiagram-v2", "  [*] --> #{graph.initial_state}"]
      graph.edges.each_value do |edge|
        arrow = "  #{edge.from} --> #{edge.to}"
        lines << (edge.event_names.empty? ? arrow : "#{arrow} : #{edge.event_names.join(" / ")}")
      end
      "#{lines.join("\n")}\n"
    end
  end
end
