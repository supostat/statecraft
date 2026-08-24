# frozen_string_literal: true

class OrderTransition < ApplicationRecord
  def readonly? = persisted?
end
