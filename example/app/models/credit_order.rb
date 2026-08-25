# frozen_string_literal: true

# The STI descendant shares the machine, the log and the scopes of Order —
# what differs is a domain fact, stated polymorphically.
class CreditOrder < Order
  # Credit money moves only through the admin paths: the customer cancel is
  # not offered to this type at all.
  def customer_cancellable?
    false
  end
end
