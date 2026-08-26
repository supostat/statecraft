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

    expect { described_class.call(payment: payment) }
      .to transition(payment).from(:pending).to(:captured).via_event(:capture)

    expect(payment.order).to have_transitioned_to(:paid)
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
