# frozen_string_literal: true

# The convention for every service here: a service earns its file at TWO OR
# MORE orchestrated steps or models; a single transition stays a verb call in
# its controller — that IS the gem's pattern, and hiding it behind a service
# would unteach it. Services are plain callables: keyword arguments in, the
# record out, and exceptions — the gem's and ActiveRecord's — fly through
# untouched, because the rescue homes live at the boundaries.
class PlaceOrder
  def self.call(user:, cart:, customer_name:, express: false, credit: false)
    raise ArgumentError, "the cart is empty" if cart.empty?

    order_class = credit ? CreditOrder : Order
    ActiveRecord::Base.transaction do
      order = order_class.create!(
        number: "ORD-#{2000 + Order.count + 1}",
        customer_name: customer_name,
        express: express,
        user: user
      )
      cart.each do |product_id, quantity|
        product = Product.find(product_id)
        order.items.create!(product: product, quantity: quantity,
                            unit_price_cents: product.price_cents)
      end
      order
    end
  end
end
