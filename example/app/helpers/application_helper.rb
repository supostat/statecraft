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

  # Bypass is not an event, so it never appears in via: the button shows
  # when the role owns the bypass right and the graph has a cancellable
  # edge from here.
  def bypass_cancel_available?(record)
    can?(:bypass_cancel, record) &&
      OrderFlow.transitions_from(record[:state]).any? { |edge| edge[:to] == :cancelled }
  end

  SHIPPING_STATUS = {
    "pending" => "Preparing",
    "packed" => "Packed",
    "shipped" => "On its way",
    "delivered" => "Delivered"
  }.freeze

  def shipping_status(shipment)
    SHIPPING_STATUS.fetch(shipment[:state], shipment[:state])
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
