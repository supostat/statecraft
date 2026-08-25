# frozen_string_literal: true

# The order scenario library. Every helper walks the honest pipeline;
# create! appears only for birth in the initial state. Helpers return the
# records they made; specs find them by attributes.
module OrderSeeds
  module_function

  def place_order(number:, customer:, items:, credit: false, express: false, user: nil)
    order_class = credit ? CreditOrder : Order
    owner = user || User.where(role: "user").order(:id).first
    order = order_class.create!(number: number, customer_name: customer, express: express,
                                user: owner)
    items.each do |product_name, quantity|
      product = Product.find_by!(name: product_name)
      order.items.create!(product: product, quantity: quantity,
                          unit_price_cents: product.price_cents)
    end
    order
  end

  # The two-role payment flow in seed form: the customer's Pay creates the
  # pending payment, the operator's confirmation is the SAME service the
  # desk uses — one link, one code path.
  def pay_order(order)
    payment = Payment.create!(number: "PAY-#{order.number}", order: order,
                              amount_cents: order.total_cents)
    ConfirmPayment.call(payment: payment)
    # The service pays payment.order — a different instance; reload so the
    # caller's snapshot is not stale.
    order.reload
  end

  def request_payment(order)
    Payment.create!(number: "PAY-#{order.number}", order: order,
                    amount_cents: order.total_cents)
    order
  end

  def ship_order(order)
    shipment = Shipment.create!(number: "SHIP-#{order.number}", order: order)
    shipment.pack!(metadata: { "note" => "seeded packing" })
    shipment.ship!(metadata: { "note" => "seeded shipping" }) if shipment.reload[:state] == "packed"
    shipment
  end

  # The out-of-band mutation for the TOCTOU scene: the shipment sails between
  # the render and the click, and refundable? flips under the open card.
  def ship_items(order)
    ship_order(order)
    order.reload
  end

  # readme: seed-pattern
  # The refusal scenario WITH its narrative: the rescue is part of the plot —
  # a cancellation attempt without a reason lands in the operations feed as a
  # refusal, then the reasoned retry succeeds.
  def seed_disputed_order
    order = place_order(number: "ORD-1009", customer: "Ivy Chen",
                        items: { "Ceramic vase" => 2 })
    begin
      order.cancel!(metadata: {})
    rescue Statecraft::GuardFailed
      # the refusal is the point: the feed keeps it
    end
    order.cancel!(metadata: { "reason" => "dispute resolved in the customer's favor" })
    order
  end
  # /readme
end

return if Order.any?

OrderSeeds.place_order(number: "ORD-1001", customer: "Alice Carter",
                       items: { "Reading lamp" => 1, "Wool rug" => 1 })
OrderSeeds.pay_order(
  OrderSeeds.place_order(number: "ORD-1002", customer: "Boris Ivanov",
                         items: { "Walnut desk" => 1 })
)
OrderSeeds.pay_order(
  OrderSeeds.place_order(number: "ORD-1003", customer: "Clara Schmidt",
                         items: { "Oak bookshelf" => 2 }, credit: true)
)
OrderSeeds.pay_order(
  OrderSeeds.place_order(number: "ORD-1004", customer: "Dana Lee",
                         items: { "Linen curtains" => 2 })
)
OrderSeeds.place_order(number: "ORD-1005", customer: "Egor Petrov",
                       items: { "Ceramic vase" => 1 }).then do |order|
  OrderSeeds.pay_order(order)
  order.refund!(metadata: { "note" => "seeded refund" })
end
OrderSeeds.place_order(number: "ORD-1006", customer: "Fatima Reza",
                       items: { "Reading lamp" => 2 })
          .cancel!(metadata: { "reason" => "customer asked" })
OrderSeeds.place_order(number: "ORD-1007", customer: "Grace Kim",
                       items: { "Wool rug" => 1 })
          .admin_override!(metadata: { "reason" => "fraud review" })
OrderSeeds.place_order(number: "ORD-1008", customer: "Henry Ford",
                       items: { "Ceramic vase" => 3 })
          .transition_to!(:cancelled, bypass_events: true, metadata: { "reason" => "migration cleanup" })
OrderSeeds.seed_disputed_order
