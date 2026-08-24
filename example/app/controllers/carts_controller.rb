# frozen_string_literal: true

# The cart is a session affair: {product_id => quantity}, no records until
# checkout — an anonymous customer needs no account to shop.
class CartsController < ApplicationController
  def show
    @lines = cart.map do |product_id, quantity|
      [Product.find(product_id), quantity]
    end
    @total_cents = @lines.sum { |product, quantity| product.price_cents * quantity }
  end

  def add
    product = Product.find(params[:product_id])
    cart[product.id.to_s] = cart.fetch(product.id.to_s, 0) + 1
    redirect_back fallback_location: products_path, notice: "#{product.name} added to your cart."
  end

  def remove
    cart.delete(params[:product_id].to_s)
    redirect_to cart_path, notice: "Removed from your cart."
  end

  private

  def cart
    session[:cart] ||= {}
  end
end
