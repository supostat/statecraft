# frozen_string_literal: true

module ApplicationHelper
  # The button = the machine's OFFERING crossed with the role's PERMISSION:
  # offerable_events is the graph filtered by the record layer of the guards
  # (a credit order is not offered cancel at all), can? says who may fire.
  # Input guards stay out on purpose — a guard that reads metadata refuses
  # INPUT, not possibility, and hiding the button would hide the form the
  # input arrives through. The panel is the full guard-aware prediction;
  # the flash is the execution.
  def permitted_actions(record)
    record.offerable_events.select { |event| can?(event, record) }
  end

  # The mirror of permitted_actions: events the graph and the role allow
  # while the record layer refuses — paired with the refusing guards, so
  # the desk can say WHY a button is absent. Names only: the words belong
  # to the view.
  def refused_actions(record)
    machine = record.class.statecraft_mounting.machine_class
    offered = record.offerable_events
    machine.transitions_from(current_state(record))
           .flat_map { |edge| edge[:events] }
           .select { |event| can?(event, record) && !offered.include?(event) }
           .map { |event| [event, record.refusals_for(event)] }
  end

  # The mounting knows which column holds the state — reading a literal
  # :state would quietly assume the default of the column: option.
  def current_state(record)
    record[record.class.statecraft_mounting.column]
  end

  # Bypass is not an event, so it never appears in via: the button shows
  # when the role owns the bypass right and the graph has a cancellable
  # edge from here.
  def bypass_cancel_available?(record)
    can?(:bypass_cancel, record) &&
      OrderFlow.transitions_from(current_state(record)).any? { |edge| edge[:to] == :cancelled }
  end

  SHIPPING_STATUS = {
    "pending" => "Preparing",
    "packed" => "Packed",
    "shipped" => "On its way",
    "delivered" => "Delivered"
  }.freeze

  def shipping_status(shipment)
    state = current_state(shipment)
    SHIPPING_STATUS.fetch(state, state)
  end

  def price(cents)
    format("$%.2f", cents / 100.0)
  end

  # The zone drives density and the header band; the storefront and the
  # operator desk share tokens and differ by this one class.
  def operator_zone?
    request.path.start_with?("/admin")
  end

  # Consecutive feed rows of one record are a cascade's footprint; both rows
  # of the pair share a tint so the inverted order reads as one story.
  def cascade_pair?(entries, index)
    neighbors = []
    neighbors << entries[index - 1] if index.positive?
    neighbors << entries[index + 1] if index + 1 < entries.size
    entry = entries[index]
    neighbors.any? do |neighbor|
      neighbor.record_class == entry.record_class && neighbor.record_id == entry.record_id
    end
  end
end
