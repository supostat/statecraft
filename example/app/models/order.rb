# frozen_string_literal: true

class Order < ApplicationRecord
  state_machine OrderFlow, helpers: true, scopes: true
end
