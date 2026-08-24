# frozen_string_literal: true

# The operator's order list: an unknown or empty state filter honestly means
# "all". Scope validation lives here so the controller never guesses.
class OrdersQuery
  def self.call(state: nil)
    scope = state.to_s
    relation = OrderFlow.states.map(&:to_s).include?(scope) ? Order.public_send(scope) : Order.all
    relation.order(:number)
  end
end
