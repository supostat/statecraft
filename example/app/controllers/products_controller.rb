# frozen_string_literal: true

class ProductsController < ApplicationController
  def index
    @products = Product.order(:name)
  end
end
