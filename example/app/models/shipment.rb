# frozen_string_literal: true

class Shipment < ApplicationRecord
  state_machine ShipmentFlow, helpers: true, scopes: true
end
