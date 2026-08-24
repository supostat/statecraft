# frozen_string_literal: true

class PaymentTransition < ApplicationRecord
  def readonly? = persisted?
end
