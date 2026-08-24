# frozen_string_literal: true

# The customer's orders, newest first. A query class owns every non-trivial
# record selection; controllers never build relations themselves.
class MyOrdersQuery
  def self.call(user:)
    Order.where(user_id: user.id).order(created_at: :desc)
  end
end
