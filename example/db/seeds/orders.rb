# frozen_string_literal: true

# The chapter's scenario library: every helper seeds THROUGH the pipeline —
# insert_all'ing log rows would be a second writer past the pipeline, a
# painted history that lies on the card. create! is birth in pending only.
# Helpers return the records they made; specs find them by attributes.
module OrderSeeds
  module_function

  def seed_fresh_order
    Order.create!(number: "ORD-FRESH")
  end

  def seed_paid_order(credit: false, number: nil)
    order_class = credit ? CreditOrder : Order
    order = order_class.create!(number: number || (credit ? "ORD-CREDIT-PAID" : "ORD-PAID"))
    order.pay!(metadata: { "note" => "seeded payment" })
    order
  end

  def seed_refundable_order
    seed_paid_order(number: "ORD-REFUNDABLE")
  end

  def seed_refunded_order
    order = seed_paid_order(number: "ORD-REFUNDED")
    order.refund!(metadata: { "note" => "seeded refund" })
    order
  end

  def seed_cancelled_by_event
    order = Order.create!(number: "ORD-CANCELLED-EVENT")
    order.cancel!(metadata: { "reason" => "customer asked" })
    order
  end

  def seed_cancelled_by_override
    order = Order.create!(number: "ORD-CANCELLED-OVERRIDE")
    order.admin_override!(metadata: { "reason" => "fraud review" })
    order
  end

  def seed_cancelled_by_bypass
    order = Order.create!(number: "ORD-CANCELLED-BYPASS")
    order.transition_to!(:cancelled, bypass_events: true, metadata: { "reason" => "migration cleanup" })
    order
  end

  # readme: seed-pattern
  # The refusal scenario WITH its narrative: the rescue is part of the plot —
  # a cancellation attempt without a reason lands in the operations feed as a
  # refusal, then the reasoned retry succeeds.
  def seed_disputed_order
    order = Order.create!(number: "ORD-DISPUTED")
    begin
      order.cancel!(metadata: {})
    rescue Statecraft::GuardFailed
      # the refusal is the point: the feed keeps it
    end
    order.cancel!(metadata: { "reason" => "dispute resolved in the customer's favor" })
    order
  end
  # /readme

  # The out-of-band mutation for the TOCTOU scene: items ship between the
  # render and the click, and refundable? flips under the open card.
  def ship_items(order, count: 1)
    order.class.where(id: order.id).update_all(shipped_items_count: count)
    order.reload
  end
end

OrderSeeds.seed_fresh_order
OrderSeeds.seed_paid_order
OrderSeeds.seed_paid_order(credit: true)
OrderSeeds.seed_refundable_order
OrderSeeds.seed_refunded_order
OrderSeeds.seed_cancelled_by_event
OrderSeeds.seed_cancelled_by_override
OrderSeeds.seed_cancelled_by_bypass
OrderSeeds.seed_disputed_order
