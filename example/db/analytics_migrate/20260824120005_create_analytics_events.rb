# frozen_string_literal: true

class CreateAnalyticsEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :analytics_events do |t|
      t.string :name, null: false
      t.string :state, null: false, default: "recorded", index: true
      t.timestamps null: false
    end

    add_check_constraint :analytics_events, "state IN ('recorded', 'archived')",
                         name: "analytics_events_state_check"

    # The log's foreign key follows the gem's convention — base_class name,
    # demodulized: Analytics::Event -> event_id.
    create_table :analytics_event_transitions do |t|
      t.bigint :event_id, null: false
      t.string :from_state, null: false
      t.string :to_state, null: false
      t.string :event
      t.column :metadata, :jsonb, null: false, default: {}
      t.datetime :created_at, null: false
      t.index %i[event_id id]
    end

    add_foreign_key :analytics_event_transitions, :analytics_events,
                    column: :event_id, on_delete: :cascade
  end
end
