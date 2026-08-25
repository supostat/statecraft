# frozen_string_literal: true

module My
  # The customer's orders: session-scoped, described in human words. The
  # gem's error texts never surface here — refusals become storefront
  # language, and the mechanics stay in the operator zone.
  class OrdersController < ApplicationController
    # The staleness family in storefront words: the record moved on while
    # the customer was looking — show the fresh card, say it humanly.
    rescue_from Statecraft::InvalidTransition, Statecraft::TransitionConflict do |error|
      redirect_to my_order_path(error.record),
                  alert: "This order just changed — here is its current state."
    end

    # The scoped query makes other people's orders invisible, and the top-bar
    # switcher returns to the page it was pressed on — so landing on a foreign
    # order as the new person is a normal walk, not an error page.
    rescue_from ActiveRecord::RecordNotFound do
      redirect_to my_orders_path,
                  alert: "That order belongs to a different account — here are your orders."
    end

    def index
      @orders = MyOrdersQuery.call(user: current_user)
    end

    def show
      @order = my_order
    end

    # The customer's half of the two-role payment flow: Pay creates the
    # pending payment for the order's total; an operator confirms it later.
    def pay
      order = my_order
      authorize! :pay, order
      if order.payment.present? || order[:state] != "pending"
        redirect_to my_order_path(order), alert: "This order cannot be paid again."
      else
        Payment.create!(number: "PAY-#{order.number}", order: order,
                        amount_cents: order.total_cents)
        redirect_to my_order_path(order),
                    notice: "Payment received — we are confirming it now."
      end
    end

    def cancel
      order = my_order
      authorize! :cancel, order
      order.cancel!(metadata: { "reason" => params.dig(:metadata, :reason).to_s })
      redirect_to my_order_path(order), notice: "Your order has been cancelled."
    rescue Statecraft::GuardFailed
      redirect_to my_order_path(order),
                  alert: "We couldn't cancel this order: please tell us the reason — " \
                         "and note that credit orders are cancelled by support only."
    end

    private

    def my_order
      MyOrdersQuery.call(user: current_user).find(params[:id])
    end
  end
end
