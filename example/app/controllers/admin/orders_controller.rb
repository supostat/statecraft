# frozen_string_literal: true

module Admin
  # readme: order-controller
  # The operator's order desk — bang everywhere: an operator wants the gem's
  # message for the flash, and a non-bang false carries no text. Staleness
  # heals in ApplicationController; a guard refusal is local to this form.
  class OrdersController < BaseController
    def index
      @orders = OrdersQuery.call(state: params[:state])
      @active_state = params[:state].to_s
    end

    def show
      @order = Order.find(params[:id])
      @metadata = {}
    end

    def pay
      fire(:pay)
    end

    def cancel
      fire(:cancel)
    end

    def refund
      fire(:refund)
    end

    # The non-mutating submit of the SAME fields: the panel recomputes from
    # exactly the metadata a real fire would carry. Nothing is written.
    def preview
      @order = Order.find(params[:id])
      @metadata = submitted_metadata
      flash.now[:notice] = "Preview only — nothing was written."
      render :show
    end

    # The privileged event: a SECOND event on the same edge, without a
    # guard — the log will name it admin_override.
    def admin_override
      order = Order.find(params[:id])
      authorize! :admin_override, order
      order.admin_override!(metadata: { "reason" => "admin override" })
      redirect_to admin_order_path(order),
                  notice: "admin_override fired: the order is now #{order[:state]}."
    end

    # The bypass: the same edge with the event layer skipped — the log
    # writes event: nil and the history renders the muted
    # "direct (bypassed events)".
    def bypass_cancel
      order = Order.find(params[:id])
      authorize! :bypass_cancel, order
      order.transition_to!(:cancelled, bypass_events: true,
                                       metadata: { "reason" => "bypassed by admin" })
      redirect_to admin_order_path(order),
                  notice: "bypassed: the order is now #{order[:state]}."
    end

    def create_shipment
      order = Order.find(params[:id])
      authorize! :create_shipment, order
      shipment = CreateShipment.call(order: order)
      redirect_to admin_shipment_path(shipment), notice: "Shipment created."
    rescue ArgumentError => error
      redirect_to admin_order_path(order), alert: error.message.capitalize + "."
    end

    private

    def fire(event_name)
      @order = Order.find(params[:id])
      authorize! event_name, @order
      @metadata = submitted_metadata
      @order.fire!(event_name, metadata: @metadata)
      redirect_to admin_order_path(@order),
                  notice: "#{event_name} fired: the order is now #{@order[:state]}."
    rescue Statecraft::GuardFailed => error
      # Local to the form: re-render THIS card with the panel computed from
      # the metadata that were actually submitted — a guard refusal belongs
      # to the scene, not to a global handler.
      flash.now[:alert] = "Refused: #{error.message}"
      render :show, status: :unprocessable_entity
    end

    def submitted_metadata
      params.fetch(:metadata, {}).permit(:reason).to_h
    end
  end
  # /readme
end
