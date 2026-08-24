# frozen_string_literal: true

class Order < ApplicationRecord
  state_machine OrderFlow, helpers: true, scopes: true

  has_many :items, class_name: "OrderItem", dependent: :destroy
  has_one :payment, dependent: :destroy
  has_one :shipment, dependent: :destroy

  def total_cents
    items.sum("quantity * unit_price_cents")
  end
end
