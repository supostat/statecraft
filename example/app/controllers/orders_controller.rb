# frozen_string_literal: true

# Bang everywhere: a controller wants the gem's message for the flash, and a
# non-bang false carries no text — "try quietly" is the idiom for jobs, not
# for scenes.
class OrdersController < ApplicationController
  def index
    scope = params[:state].to_s
    @orders = OrderFlow.states.map(&:to_s).include?(scope) ? Order.public_send(scope) : Order.all
    @orders = @orders.order(:number)
    @active_state = scope
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

  private

  def fire(event_name)
    @order = Order.find(params[:id])
    @metadata = submitted_metadata
    @order.fire!(event_name, metadata: @metadata)
    redirect_to order_path(@order), notice: "#{event_name} fired: the order is now #{@order[:state]}."
  rescue Statecraft::GuardFailed => error
    # Local to the form: re-render THIS card with the panel computed from the
    # metadata that were actually submitted — a guard refusal belongs to the
    # scene, not to a global handler.
    flash.now[:alert] = "Refused: #{error.message}"
    render :show, status: :unprocessable_entity
  end

  def submitted_metadata
    params.fetch(:metadata, {}).permit(:reason).to_h
  end
end
