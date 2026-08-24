# frozen_string_literal: true

class Product < ApplicationRecord
  has_many :order_items, dependent: :restrict_with_exception

  validates :name, presence: true
  validates :price_cents, numericality: { greater_than: 0 }
end
