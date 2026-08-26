# frozen_string_literal: true

require "tmpdir"
require "rails/generators"
require "generators/statecraft/from_statesman/from_statesman_generator"

# The conversion end to end: a statesman schema shaped like their generator's
# output, seeded with history, is migrated by the three generated migrations
# and then carries a live statecraft transition. PostgreSQL only — the
# conversion leans on window functions, NOT VALID validations, concurrent
# index builds and a USING cast; the sqlite branches of the templates stay
# proven by the generator spec's textual checks alone.
RSpec.describe "statesman conversion", :wire do
  before do
    skip "the conversion is PostgreSQL-only" unless SpecDatabase.postgres?
  end

  let(:machine_fixture) do
    Class.new do
      def self.states = %w[pending paid shipped]
      def self.initial_state = "pending"
      def self.successors = { "pending" => ["paid"], "paid" => ["shipped"], "shipped" => ["pending"] }
      def self.callbacks = { guards: [] }
    end
  end

  def create_statesman_schema
    connection = ActiveRecord::Base.connection
    connection.drop_table(:order_transitions, if_exists: true, force: :cascade)
    connection.drop_table(:orders, if_exists: true, force: :cascade)

    # The shape statesman's own generator emits: no state column on the
    # parent, and a transitions table keyed by sort_key with most_recent,
    # text metadata and both unique indexes.
    connection.create_table :orders do |t|
      t.string :number
      t.timestamps null: false
    end

    connection.create_table :order_transitions do |t|
      t.string :to_state, null: false
      t.text :metadata, default: "{}"
      t.integer :sort_key, null: false
      t.integer :order_id, null: false
      t.boolean :most_recent, null: false
      t.timestamps null: false
    end
    connection.add_index :order_transitions, %i[order_id sort_key], unique: true
    connection.add_index :order_transitions, %i[order_id most_recent],
                         unique: true, where: "most_recent"
    connection.add_foreign_key :order_transitions, :orders
  end

  def seed_statesman_history
    connection = ActiveRecord::Base.connection
    walked = connection.insert("INSERT INTO orders (number, created_at, updated_at) " \
                               "VALUES ('ORD-1', NOW(), NOW())")
    untouched = connection.insert("INSERT INTO orders (number, created_at, updated_at) " \
                                  "VALUES ('ORD-2', NOW(), NOW())")

    [["paid", 10, false, "2026-08-01"], ["shipped", 20, true, "2026-08-02"]].each do |to, key, recent, day|
      connection.insert(<<~SQL)
        INSERT INTO order_transitions
          (to_state, metadata, sort_key, order_id, most_recent, created_at, updated_at)
        VALUES ('#{to}', '{"reason":"seeded"}', #{key}, #{walked}, #{recent}, '#{day}', '#{day}')
      SQL
    end

    [walked, untouched]
  end

  def generate_migrations(destination)
    stub_const("OrderStateMachine", machine_fixture)
    Statecraft::Generators::FromStatesmanGenerator.start(
      ["Order", "--quiet"], destination_root: destination
    )
  end

  def run_migration(destination, step)
    path = Dir[File.join(destination, "db/migrate/*_convert_order_transitions_#{step}.rb")].first
    expect(path).not_to be_nil, "the #{step} migration was not generated"
    load path
    migration_class = Object.const_get("ConvertOrderTransitions#{step.capitalize}")
    migration_class.new.migrate(:up)
    migration_class
  end

  def mount_converted_model(destination)
    load File.join(destination, "app/state_machines/application_machine.rb")
    load File.join(destination, "app/state_machines/order_flow.rb")

    stub_const("OrderTransition", Class.new(ActiveRecord::Base) do
      self.table_name = "order_transitions"
    end)
    stub_const("Order", Class.new(ActiveRecord::Base) do
      self.table_name = "orders"
    end)

    # Mounting AFTER stub_const: inside a Class.new body the model has no
    # name yet, and the log-class convention is derived from it.
    Order.state_machine(OrderFlow, changed_at: true)
  end

  it "converts a live statesman table into the statecraft log and keeps transitioning" do
    Dir.mktmpdir("statecraft-conversion") do |tmp|
      create_statesman_schema
      walked_id, untouched_id = seed_statesman_history
      generate_migrations(tmp)
      connection = ActiveRecord::Base.connection

      run_migration(tmp, "ddl")
      backfill = run_migration(tmp, "backfill")

      # The runbook's catch-up step lives HERE, between the backfill and the
      # finalize: rerunning is idempotent while sort_key is still alive, and
      # finalize drops the very column the backfill reads.
      caught_up = connection.select_all("SELECT id, from_state FROM order_transitions ORDER BY id").to_a
      expect { backfill.new.up }.not_to raise_error
      expect(connection.select_all("SELECT id, from_state FROM order_transitions ORDER BY id").to_a)
        .to eq(caught_up)

      run_migration(tmp, "finalize")

      # The parent carries the last transition by sort_key, and the moment it
      # happened; a record that never transitioned stays initial with no
      # changed_at, exactly like a freshly created one.
      walked = connection.select_one("SELECT state, state_changed_at FROM orders WHERE id = #{walked_id}")
      untouched = connection.select_one("SELECT state, state_changed_at FROM orders WHERE id = #{untouched_id}")
      expect(walked["state"]).to eq("shipped")
      expect(walked["state_changed_at"].to_s).to start_with("2026-08-02")
      expect(untouched["state"]).to eq("pending")
      expect(untouched["state_changed_at"]).to be_nil

      # The imported history reads as direct transitions with a restored
      # chain: the first hop starts from the initial state.
      imported = connection.select_all(
        "SELECT from_state, to_state, event, metadata FROM order_transitions " \
        "WHERE order_id = #{walked_id} ORDER BY id"
      ).to_a
      expect(imported.map { |row| [row["from_state"], row["to_state"]] })
        .to eq([%w[pending paid], %w[paid shipped]])
      expect(imported.map { |row| row["event"] }).to all(be_nil)
      expect(connection.select_value("SELECT metadata->>'reason' FROM order_transitions " \
                                     "WHERE order_id = #{walked_id} ORDER BY id LIMIT 1"))
        .to eq("seeded")

      # The statesman columns are gone and the state column is indexed — the
      # reference schema's promise the first conversion forgot.
      expect(connection.columns(:order_transitions).map(&:name))
        .not_to include("sort_key", "most_recent", "updated_at")
      expect(connection.indexes(:orders).flat_map(&:columns)).to include("state")

      # And the converted table keeps working as a statecraft log.
      mount_converted_model(tmp)
      order = Order.find(walked_id)
      expect(order.history.count).to eq(2)

      transition = order.transition_to!(:pending, metadata: { "reason" => "returned" })

      expect(transition.from_state).to eq("shipped")
      expect(transition.to_state).to eq("pending")
      expect(order.reload[:state]).to eq("pending")
      expect(order[:state_changed_at]).not_to be_nil
      expect(order.history.count).to eq(3)
      expect(order.history.last.metadata).to eq("reason" => "returned")
    ensure
      %i[ConvertOrderTransitionsDdl ConvertOrderTransitionsBackfill
         ConvertOrderTransitionsFinalize ApplicationMachine OrderFlow].each do |loaded_constant|
        Object.send(:remove_const, loaded_constant) if Object.const_defined?(loaded_constant)
      end
      ActiveRecord::Base.connection.drop_table(:order_transitions, if_exists: true, force: :cascade)
      ActiveRecord::Base.connection.drop_table(:orders, if_exists: true, force: :cascade)
    end
  end
end
