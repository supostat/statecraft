# frozen_string_literal: true

# Append-only transition log for Shop::Order. This is a read-model:
# scopes, reading methods and serializers are yours; the transition pipeline
# writes rows through the insert path and never calls validations or
# callbacks declared here.
class Shop::OrderTransition < ApplicationRecord
  def readonly? = persisted?
end
