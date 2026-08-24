# frozen_string_literal: true

class CheckoutsController < ApplicationController
  def new
    redirect_to products_path, alert: "Your cart is empty." and return if cart.empty?

    @lines = cart.map { |product_id, quantity| [Product.find(product_id), quantity] }
    @total_cents = @lines.sum { |product, quantity| product.price_cents * quantity }
  end

  # Birth in the initial state is the one sanctioned create!: the order and
  # its items appear atomically, prices fixed at this very moment.
  def create
    redirect_to products_path, alert: "Your cart is empty." and return if cart.empty?

    order_class = params[:credit] == "1" ? CreditOrder : Order
    order = nil
    ActiveRecord::Base.transaction do
      order = order_class.create!(
        number: "ORD-#{2000 + Order.count + 1}",
        customer_name: params.require(:customer_name),
        express: params[:express] == "1",
        user: current_user
      )
      cart.each do |product_id, quantity|
        product = Product.find(product_id)
        order.items.create!(product: product, quantity: quantity,
                            unit_price_cents: product.price_cents)
      end
    end

    session[:cart] = {}
    redirect_to my_order_path(order), notice: "Order #{order.number} placed — thank you!"
  end

  private

  def cart
    session[:cart] ||= {}
  end
end
