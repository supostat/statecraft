# frozen_string_literal: true

class Shop::Order < ApplicationRecord
  state_machine Shop::OrderFlow, changed_at: true, helpers: true, scopes: true
end
