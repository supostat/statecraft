# frozen_string_literal: true

module Admin
  class OrdersController < ApplicationController
    def show
      @order = Order.find(params[:id])
    end

    # The privileged event: a SECOND event on the same edge, without a guard —
    # the log will name it admin_override.
    def admin_override
      order = Order.find(params[:id])
      order.admin_override!(metadata: { "reason" => "admin override" })
      redirect_to admin_order_path(order), notice: "admin_override fired: the order is now #{order[:state]}."
    end

    # The bypass: the same edge with the event layer skipped — the log writes
    # event: nil and the history renders the muted "direct (bypassed events)".
    def bypass_cancel
      order = Order.find(params[:id])
      order.transition_to!(:cancelled, bypass_events: true, metadata: { "reason" => "bypassed by admin" })
      redirect_to admin_order_path(order), notice: "bypassed: the order is now #{order[:state]}."
    end
  end
end
