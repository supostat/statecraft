# frozen_string_literal: true

class CreateStoreDomain < ActiveRecord::Migration[8.1]
  def up
    # The harness-era rows are scenic seeds with no domain meaning: orders
    # without items, payments and shipments without orders. The shop starts
    # clean; seeds v2 rebuild the world through the honest pipeline.
    execute "DELETE FROM payment_transitions"
    execute "DELETE FROM payments"
    execute "DELETE FROM shipment_transitions"
    execute "DELETE FROM shipments"
    execute "DELETE FROM order_transitions"
    execute "DELETE FROM orders"
    execute "DELETE FROM operation_entries"

    create_table :products do |t|
      t.string :name, null: false
      t.integer :price_cents, null: false
      t.timestamps null: false
    end

    create_table :order_items do |t|
      t.references :order, null: false, foreign_key: { on_delete: :cascade }
      t.references :product, null: false, foreign_key: true
      t.integer :quantity, null: false, default: 1
      # The price is fixed at order time: a catalog price change never
      # rewrites history.
      t.integer :unit_price_cents, null: false
      t.datetime :created_at, null: false
    end

    add_column :orders, :customer_name, :string
    add_column :orders, :express, :boolean, null: false, default: false
    remove_column :orders, :shipped_items_count

    add_reference :payments, :order, null: false,
                                     foreign_key: { on_delete: :cascade },
                                     index: { unique: true }
    add_reference :shipments, :order, null: false,
                                      foreign_key: { on_delete: :cascade },
                                      index: { unique: true }
    # Express is the order's promise, not the shipment's: the column moves up.
    remove_column :shipments, :express
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
