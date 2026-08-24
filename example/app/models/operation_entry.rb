# frozen_string_literal: true

# Application furniture, not a statecraft log: an ordinary ActiveRecord table
# the telemetry subscriber writes with create!. None of the gem's guarantees
# apply here — no readonly, no insert path, no protocol. Feed order is
# insertion order, which is what makes the after_commit inversion visible.
class OperationEntry < ApplicationRecord
  scope :feed, -> { order(:id) }
end
