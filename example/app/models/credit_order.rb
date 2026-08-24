# frozen_string_literal: true

# The STI descendant shares the machine, the log and the scopes of Order —
# what differs is how guards branch on the type.
class CreditOrder < Order
end
