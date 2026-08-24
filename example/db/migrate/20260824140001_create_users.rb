# frozen_string_literal: true

class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :name, null: false
      t.string :role, null: false, default: "user"
      t.timestamps null: false
    end

    add_check_constraint :users, "role IN ('user', 'manager', 'admin')",
                         name: "users_role_check"

    # Nullable on purpose: orders from the pre-role era stay legal — the
    # operator zone sees them, "my orders" shows only owned ones.
    add_reference :orders, :user, null: true, foreign_key: true
  end
end
