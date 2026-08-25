# frozen_string_literal: true

# A placed order whose customer already pressed Pay: the payment waits
# pending for an operator's confirmation — the card-minimum scene.
return if Order.exists?(number: "ORD-1012")

OrderSeeds.request_payment(
  OrderSeeds.place_order(number: "ORD-1012", customer: "Leo Wong",
                         items: { "Reading lamp" => 3 })
)
