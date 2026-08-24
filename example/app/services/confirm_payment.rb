# frozen_string_literal: true

# The operator's half of the two-role payment flow: confirming a payment
# captures it AND pays its order — one visible two-step link, no cross-model
# callback magic. Both transitions run the real pipeline; a stale or
# conflicting state raises the gem's own error to the caller.
class ConfirmPayment
  def self.call(payment:)
    payment.capture!(metadata: {})
    payment.order.pay!(metadata: { "note" => "payment #{payment.number} confirmed" })
    payment
  end
end
