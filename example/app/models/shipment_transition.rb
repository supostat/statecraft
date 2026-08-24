# frozen_string_literal: true

class ShipmentTransition < ApplicationRecord
  def readonly? = persisted?
end
