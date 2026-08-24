# frozen_string_literal: true

class ShipmentFlow
  include Statecraft::Machine

  state :pending, initial: true
  state :packed
  state :shipped
  state :delivered

  event :pack, from: :pending, to: :packed
  event :ship, from: :packed, to: :shipped
  event :deliver, from: :shipped, to: :delivered

  # The one cascade, and it is conditional: express shipments sail on pack,
  # ordinary ones wait in packed. Deliver stays a human's click everywhere —
  # the e2e proves a chain never fires where none is declared.
  after_transition :auto_ship_express, to: :packed

  private

  def auto_ship_express(record, _metadata)
    record.ship!(metadata: { "note" => "express auto-ship" }) if record.express?
  end
end
