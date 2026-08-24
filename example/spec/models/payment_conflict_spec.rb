# frozen_string_literal: true

require "rails_helper"

# catalog: 30-deterministic-conflict
# catalog: 31-n-thread-race

RSpec.describe "payment conflicts" do
  def pending_payment(number)
    order = OrderSeeds.place_order(number: "ORD-#{number}", customer: "Spec Operator",
                                   items: { "Reading lamp" => 1 })
    Payment.create!(number: number, order: order, amount_cents: order.total_cents)
  end

  describe "the deterministic conflict — no threads needed" do
    it "raises TransitionConflict when the instance is stale, and writes no log row" do
      payment = pending_payment("SPEC-STALE")
      stale = Payment.find(payment.id)
      # Out of band, past the pipeline: exactly the write a concurrent
      # operator's committed transaction leaves behind.
      Payment.where(id: payment.id).update_all(state: "captured")

      expect { stale.capture!(metadata: {}) }.to raise_error(Statecraft::TransitionConflict)
      expect(PaymentTransition.where(payment_id: payment.id)).to be_empty
    end
  end

  # Threads run on their own connections and cannot see this example's
  # uncommitted data, so the race is the one named non-transactional
  # exception of the suite — it creates, commits and cleans up after itself.
  describe "the N-thread race (PostgreSQL)" do
    self.use_transactional_tests = false

    it "lets exactly one of four threads win; the rest get TransitionConflict; one log row" do
      payment = pending_payment("SPEC-RACE")
      racers = Array.new(4) { Payment.find(payment.id) }

      outcomes = racers.map do |racer|
        Thread.new do
          racer.capture!(metadata: {})
          :captured
        rescue Statecraft::TransitionConflict
          :conflict
        end
      end.map(&:value)

      expect(outcomes.tally).to eq(captured: 1, conflict: 3)
      expect(PaymentTransition.where(payment_id: payment.id).count).to eq(1)
    ensure
      order = payment.order
      PaymentTransition.where(payment_id: payment.id).delete_all
      OperationEntry.where(record_class: "Payment", record_id: payment.id.to_s).delete_all
      Payment.where(id: payment.id).delete_all
      OrderTransition.where(order_id: order.id).delete_all
      OperationEntry.where(record_class: "Order", record_id: order.id.to_s).delete_all
      Order.where(id: order.id).delete_all
    end
  end
end
