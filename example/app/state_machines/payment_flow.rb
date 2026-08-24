# frozen_string_literal: true

class PaymentFlow
  include Statecraft::Machine

  state :pending, initial: true
  state :captured

  # The lock cluster: SELECT FOR UPDATE + reload before the guards, so a
  # dirty record refuses up front and a stale one meets the same
  # TransitionConflict the CAS would report — observed early.
  event :capture, from: :pending, to: :captured, lock: true
end
