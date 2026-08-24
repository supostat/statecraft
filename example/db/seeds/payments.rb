# frozen_string_literal: true

module PaymentSeeds
  module_function

  def seed_pending_payment
    Payment.create!(number: "PAY-PENDING", amount_cents: 4900)
  end

  def seed_captured_payment
    payment = Payment.create!(number: "PAY-CAPTURED", amount_cents: 12_000)
    payment.capture!(metadata: {})
    payment
  end
end

PaymentSeeds.seed_pending_payment
PaymentSeeds.seed_captured_payment
