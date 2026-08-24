# frozen_string_literal: true

class CreateOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :orders do |t|
      t.string :type
      t.string :number, null: false
      t.string :state, null: false, default: "pending", index: true
      t.integer :shipped_items_count, null: false, default: 0
      t.timestamps null: false
    end

    add_check_constraint :orders, "state IN ('pending', 'paid', 'refunded', 'cancelled')",
                         name: "orders_state_check"

    create_table :order_transitions do |t|
      t.references :order, null: false,
                           foreign_key: { to_table: :orders, on_delete: :cascade },
                           index: false
      t.string :from_state, null: false
      t.string :to_state, null: false
      t.string :event
      t.column :metadata, :jsonb, null: false, default: {}
      t.datetime :created_at, null: false
      t.index %i[order_id id]
    end
  end
end
