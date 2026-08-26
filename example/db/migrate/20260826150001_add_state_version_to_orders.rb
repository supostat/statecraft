# frozen_string_literal: true

class AddStateVersionToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :state_version, :bigint, null: false, default: 0
  end
end
