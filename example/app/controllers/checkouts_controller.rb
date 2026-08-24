# frozen_string_literal: true

class CheckoutsController < ApplicationController
  def new
    redirect_to products_path, alert: "Your cart is empty." and return if cart.empty?

    @lines = cart.map { |product_id, quantity| [Product.find(product_id), quantity] }
    @total_cents = @lines.sum { |product, quantity| product.price_cents * quantity }
  end

  def create
    redirect_to products_path, alert: "Your cart is empty." and return if cart.empty?

    order = PlaceOrder.call(
      user: current_user,
      cart: cart,
      customer_name: params.require(:customer_name),
      express: params[:express] == "1",
      credit: params[:credit] == "1"
    )

    session[:cart] = {}
    redirect_to my_order_path(order), notice: "Order #{order.number} placed — thank you!"
  end

  private

  def cart
    session[:cart] ||= {}
  end
end
