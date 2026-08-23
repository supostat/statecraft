# frozen_string_literal: true

# Shared on-the-fly schema for model-facing specs. Idempotent per process:
# the in-memory database lives as long as the suite, so tables are created
# once and truncated by the specs that need isolation.
module TestSchema
  def self.load!
    return if ActiveRecord::Base.connection.table_exists?(:orders)

    SpecDatabase.define_schema do
      create_table :orders, force: true do |t|
        t.string :type
        t.string :state, null: false, default: "pending"
        t.string :status, null: false, default: "draft"
        t.datetime :state_changed_at
        t.timestamps null: false
      end

      create_table :order_transitions, force: true do |t|
        t.references :order, null: false, index: false,
                             foreign_key: { to_table: :orders, on_delete: :cascade }
        t.string :from_state, null: false
        t.string :to_state, null: false
        t.string :event
        t.json :metadata, null: false, default: {}
        t.datetime :created_at, null: false
        t.index %i[order_id id]
      end
    end
  end
end
