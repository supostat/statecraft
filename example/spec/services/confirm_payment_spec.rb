# frozen_string_literal: true

require "rails_helper"

RSpec.describe ConfirmPayment do
  def pending_payment
    order = OrderSeeds.place_order(number: "SPEC-CONFIRM", customer: "Service Sue",
                                   items: { "Reading lamp" => 1 })
    Payment.create!(number: "PAY-SPEC-CONFIRM", order: order,
                    amount_cents: order.total_cents)
  end

  it "captures the payment AND pays the order — the whole two-step link" do
    payment = pending_payment

    described_class.call(payment: payment)

    expect(payment.reload[:state]).to eq("captured")
    expect(payment.order.reload[:state]).to eq("paid")
    expect(payment.order.last_transition.event).to eq("pay")
  end

  it "lets the gem's exceptions fly through untouched" do
    payment = pending_payment
    described_class.call(payment: payment)

    expect do
      described_class.call(payment: payment.reload)
    end.to raise_error(Statecraft::InvalidTransition, /no branch from captured/)
  end
end
