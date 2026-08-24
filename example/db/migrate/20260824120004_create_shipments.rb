# frozen_string_literal: true

class CreateShipments < ActiveRecord::Migration[8.1]
  def change
    create_table :shipments do |t|
      t.string :number, null: false
      t.string :state, null: false, default: "pending", index: true
      t.boolean :express, null: false, default: false
      t.timestamps null: false
    end

    add_check_constraint :shipments, "state IN ('pending', 'packed', 'shipped', 'delivered')",
                         name: "shipments_state_check"

    create_table :shipment_transitions do |t|
      t.references :shipment, null: false,
                              foreign_key: { to_table: :shipments, on_delete: :cascade },
                              index: false
      t.string :from_state, null: false
      t.string :to_state, null: false
      t.string :event
      t.column :metadata, :jsonb, null: false, default: {}
      t.datetime :created_at, null: false
      t.index %i[shipment_id id]
    end
  end
end
