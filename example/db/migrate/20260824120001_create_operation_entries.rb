# frozen_string_literal: true

class CreateOperationEntries < ActiveRecord::Migration[8.1]
  def change
    # Application furniture, not a statecraft log: an ordinary table for the
    # telemetry subscriber, with none of the gem's readonly or insert-path
    # guarantees. Feed order is insertion order (id).
    create_table :operation_entries do |t|
      t.string :record_class, null: false
      t.string :record_id, null: false
      t.string :from_state
      t.string :to_state
      t.string :event_name
      t.string :outcome, null: false
      t.string :reason
      t.datetime :created_at, null: false
    end
  end
end
