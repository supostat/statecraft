# frozen_string_literal: true

class CreateShopOrderStateMachine < ActiveRecord::Migration[8.1]
  def change
    create_table :shop_orders do |t|
      t.string :state, null: false, default: "pending", index: true
      t.datetime :state_changed_at
      t.timestamps null: false
    end

    # add new states here when the machine grows
    add_check_constraint :shop_orders, "state IN ('pending', 'paid')",
                         name: "shop_orders_state_check"

    create_table :shop_order_transitions do |t|
      t.references :order, null: false,
                                      foreign_key: { to_table: :shop_orders, on_delete: :cascade },
                                      index: false
      t.string :from_state, null: false
      t.string :to_state, null: false
      t.string :event
      t.column :metadata, metadata_column_type, null: false, default: {}
      t.datetime :created_at, null: false
      t.index %i[order_id id]
    end
  end

  private

  # jsonb where the database has it, json elsewhere: the adapter is known
  # only when the migration actually runs, never at generation time.
  def metadata_column_type
    connection.adapter_name.match?(/postg/i) ? :jsonb : :json
  end
end
