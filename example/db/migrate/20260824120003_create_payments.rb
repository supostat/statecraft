# frozen_string_literal: true

class CreatePayments < ActiveRecord::Migration[8.1]
  def change
    create_table :payments do |t|
      t.string :number, null: false
      t.string :state, null: false, default: "pending", index: true
      t.integer :amount_cents, null: false, default: 0
      t.timestamps null: false
    end

    add_check_constraint :payments, "state IN ('pending', 'captured')",
                         name: "payments_state_check"

    create_table :payment_transitions do |t|
      t.references :payment, null: false,
                             foreign_key: { to_table: :payments, on_delete: :cascade },
                             index: false
      t.string :from_state, null: false
      t.string :to_state, null: false
      t.string :event
      t.column :metadata, :jsonb, null: false, default: {}
      t.datetime :created_at, null: false
      t.index %i[payment_id id]
    end
  end
end
