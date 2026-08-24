# frozen_string_literal: true

module ApplicationHelper
  # The button = the graph's POSSIBILITY crossed with the role's PERMISSION:
  # transitions_from says what edges leave this state, can? says who may
  # fire them. Guards stay out of this on purpose — a guard that reads
  # metadata (a cancellation reason) refuses INPUT, not possibility, and
  # hiding the button would hide the form the input arrives through. The
  # panel below is the guard-aware prediction; the flash is the execution.
  def permitted_actions(record)
    machine = record.class.statecraft_mounting.machine_class
    machine.transitions_from(record[:state])
           .flat_map { |edge| edge[:events] }
           .select { |event| can?(event, record) }
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
end
