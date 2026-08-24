# frozen_string_literal: true

module Admin
  class PaymentsController < ApplicationController
    def index
      @payments = Payment.order(:number)
    end

    def show
      @payment = Payment.find(params[:id])
    end

    # The operator's half of the two-role payment flow: confirming the
    # payment captures it AND pays the order — one visible two-step link,
    # no cross-model callback magic.
    def capture
      payment = Payment.find(params[:id])
      payment.capture!(metadata: {})
      payment.order.pay!(metadata: { "note" => "payment #{payment.number} confirmed" })
      redirect_to admin_payment_path(payment),
                  notice: "capture fired: the payment is captured and the order is paid."
    end

    # The combined "save-and-capture" plot: assigning form attributes right
    # before a lock transition makes the instance dirty, and the lock path
    # refuses to reload over unsaved changes. The rescue is the scene's moral.
    def save_and_capture
      @payment = Payment.find(params[:id])
      @payment.assign_attributes(amount_params)
      @payment.capture!(metadata: {})
      redirect_to admin_payment_path(@payment), notice: "saved and captured."
    rescue Statecraft::DirtyRecordError => error
      flash.now[:alert] = "Refused: #{error.message} — don't mix persistence with a transition: " \
                          "save first, then capture."
      render :show, status: :unprocessable_entity
    end

    private

    def amount_params
      params.fetch(:payment, {}).permit(:amount_cents)
    end
  end
end
