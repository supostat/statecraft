# frozen_string_literal: true

class Payment < ApplicationRecord
  state_machine PaymentFlow, helpers: true, scopes: true
end
