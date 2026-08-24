# frozen_string_literal: true

module Admin
  class ShipmentsController < ApplicationController
    def index
      @shipments = Shipment.order(:number)
    end

    def show
      @shipment = Shipment.find(params[:id])
    end

    def pack
      fire(:pack)
    end

    def ship
      fire(:ship)
    end

    def deliver
      fire(:deliver)
    end

    private

    def fire(event_name)
      shipment = Shipment.find(params[:id])
      shipment.fire!(event_name, metadata: submitted_metadata)
      redirect_to admin_shipment_path(shipment),
                  notice: "#{event_name} fired: the shipment is now #{shipment[:state]}."
    end

    def submitted_metadata
      params.fetch(:metadata, {}).permit(:note).to_h
    end
  end
end
