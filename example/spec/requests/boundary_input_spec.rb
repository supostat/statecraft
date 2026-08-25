# frozen_string_literal: true

require "rails_helper"

# The boundary of outside input: raw POSTs that bypass every form. The
# storefront answers each one in human words — no framework exceptions,
# no silent state changes.
RSpec.describe "boundary input", type: :request do
  it "refuses paying an order twice in human words, one payment stands" do
    order = Order.find_by!(number: "ORD-1001")

    post pay_my_order_path(order)
    expect(flash[:notice]).to include("Payment received")

    post pay_my_order_path(order)
    expect(response).to redirect_to(my_order_path(order))
    expect(flash[:alert]).to eq("This order cannot be paid again.")
    expect(Payment.where(order: order).count).to eq(1)
  end

  it "asks for the name on a nameless checkout and creates nothing" do
    post add_to_cart_path(product_id: Product.find_by!(name: "Reading lamp").id)

    expect do
      post checkout_path, params: { customer_name: "   " }
    end.not_to change(Order, :count)

    expect(response).to redirect_to(checkout_path)
    expect(flash[:alert]).to eq("Please tell us your name.")
  end

  it "keeps the current identity when the switcher gets an unknown id" do
    ada = User.find_by!(role: "admin")
    post switch_user_path, params: { user_id: ada.id }

    post switch_user_path, params: { user_id: 999_999 }
    expect(response).to redirect_to(products_path)
    expect(flash[:alert]).to eq("That person is not in the demo cast.")

    get admin_orders_path
    expect(response).to have_http_status(:ok)
  end
end
