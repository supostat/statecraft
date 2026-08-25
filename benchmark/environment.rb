# frozen_string_literal: true

# Shared benchmark environment: one PostgreSQL connection, three isolated
# stacks (statecraft / aasm / statesman) with their own tables and models,
# seeding, and the environment banner every script prints. Smoke mode keeps
# every figure tiny so the compose gate finishes in seconds.
require "bundler/setup"
require "active_record"
require "statecraft"
require "aasm"
require "statesman"
require "benchmark/ips"

Statesman.configure { storage_adapter(Statesman::Adapters::ActiveRecord) }

SMOKE = ARGV.include?("--smoke")
ROW_COUNT = SMOKE ? 200 : 200_000
THREAD_COUNT = SMOKE ? 2 : 8

ActiveRecord::Base.establish_connection(
  ENV.fetch("DATABASE_URL", "postgres://statecraft:statecraft@localhost:5432/statecraft_test")
)
ActiveRecord::Base.connection_pool.disconnect!
ActiveRecord::Base.establish_connection(
  ActiveRecord::Base.connection_db_config.configuration_hash.merge(pool: THREAD_COUNT + 2)
)

%w[bench_statecraft_order_transitions bench_statecraft_orders
   bench_statesman_order_transitions bench_statesman_orders
   bench_aasm_orders].each do |leftover_table|
  ActiveRecord::Base.connection.drop_table(leftover_table, if_exists: true, force: :cascade)
end

ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table :bench_statecraft_orders, force: true do |t|
    t.string :state, null: false, default: "pending", index: true
    t.timestamps null: false
  end

  create_table :bench_statecraft_order_transitions, force: true do |t|
    t.references :statecraft_order,
                 null: false, index: false,
                 foreign_key: { to_table: :bench_statecraft_orders, on_delete: :cascade }
    t.string :from_state, null: false
    t.string :to_state, null: false
    t.string :event
    t.jsonb :metadata, null: false, default: {}
    t.datetime :created_at, null: false
    t.index %i[statecraft_order_id id],
            name: "index_bench_statecraft_transitions_on_order_and_id"
  end

  create_table :bench_aasm_orders, force: true do |t|
    t.string :state, null: false, default: "pending", index: true
    t.timestamps null: false
  end

  create_table :bench_statesman_orders, force: true do |t|
    t.timestamps null: false
  end

  create_table :bench_statesman_order_transitions, force: true do |t|
    t.string :to_state, null: false
    t.jsonb :metadata, null: false, default: {}
    t.integer :sort_key, null: false
    t.references :bench_statesman_order, null: false, index: false
    t.boolean :most_recent, null: false
    t.timestamps null: false
    t.index %i[bench_statesman_order_id sort_key],
            unique: true, name: "index_bench_statesman_transitions_parent_sort"
    t.index %i[bench_statesman_order_id most_recent],
            unique: true, where: "most_recent",
            name: "index_bench_statesman_transitions_parent_most_recent"
  end
end

CALLBACK_COUNTER = Object.new
class << CALLBACK_COUNTER
  def reset = @count = 0
  def increment = (@mutex ||= Mutex.new).synchronize { @count = (@count || 0) + 1 }
  def count = @count || 0
end

# --- statecraft stack ---------------------------------------------------

class StatecraftOrderTransition < ActiveRecord::Base
  self.table_name = "bench_statecraft_order_transitions"
end

class BenchFlow
  include Statecraft::Machine

  state :pending, initial: true
  state :paid

  event :pay, from: :pending, to: :paid
  event :reset, from: :paid, to: :pending

  after_transition :count_callback, event: [:pay]

  private

  def count_callback(_record, _transition) = CALLBACK_COUNTER.increment
end

class StatecraftOrder < ActiveRecord::Base
  self.table_name = "bench_statecraft_orders"

  state_machine BenchFlow, log: StatecraftOrderTransition, helpers: true
end

# --- aasm stack ---------------------------------------------------------

class AasmOrder < ActiveRecord::Base
  self.table_name = "bench_aasm_orders"

  include AASM

  aasm column: :state do
    state :pending, initial: true
    state :paid

    after_all_transitions :count_callback

    event :pay do
      transitions from: :pending, to: :paid
    end

    event :reset do
      transitions from: :paid, to: :pending
    end
  end

  def count_callback = CALLBACK_COUNTER.increment
end

# --- statesman stack ----------------------------------------------------

class StatesmanOrderTransition < ActiveRecord::Base
  self.table_name = "bench_statesman_order_transitions"
  # Statesman's ActiveRecordTransition module is deliberately NOT included:
  # it wires `serialize :metadata`, which native jsonb columns reject.

  belongs_to :bench_statesman_order, class_name: "StatesmanOrder"
end

class StatesmanOrder < ActiveRecord::Base
  self.table_name = "bench_statesman_orders"

  has_many :bench_statesman_order_transitions,
           class_name: "StatesmanOrderTransition",
           foreign_key: :bench_statesman_order_id

  include Statesman::Adapters::ActiveRecordQueries[
    transition_class: StatesmanOrderTransition,
    initial_state: :pending
  ]

  def state_machine
    @state_machine ||= StatesmanFlow.new(
      self,
      transition_class: StatesmanOrderTransition,
      association_name: :bench_statesman_order_transitions
    )
  end
end

class StatesmanFlow
  include Statesman::Machine

  state :pending, initial: true
  state :paid

  transition from: :pending, to: :paid
  transition from: :paid, to: :pending

  after_transition(from: :pending, to: :paid) { |_order, _transition| CALLBACK_COUNTER.increment }
end

# --- seeding and the banner ---------------------------------------------

def seed_read_corpus
  half = ROW_COUNT / 2
  now = Time.current

  [StatecraftOrder, AasmOrder].each do |model|
    rows = Array.new(ROW_COUNT) do |index|
      { state: index < half ? "paid" : "pending", created_at: now, updated_at: now }
    end
    rows.each_slice(10_000) { |slice| model.insert_all(slice) }
  end

  order_rows = Array.new(ROW_COUNT) { { created_at: now, updated_at: now } }
  order_rows.each_slice(10_000) { |slice| StatesmanOrder.insert_all(slice) }
  paid_ids = StatesmanOrder.order(:id).limit(half).pluck(:id)
  transition_rows = paid_ids.map do |order_id|
    { bench_statesman_order_id: order_id, to_state: "paid", sort_key: 10,
      most_recent: true, metadata: {}, created_at: now, updated_at: now }
  end
  transition_rows.each_slice(10_000) { |slice| StatesmanOrderTransition.insert_all(slice) }

  # Freshly bulk-loaded tables are not what production reads: the first
  # scanner pays for hint bits and the visibility map is empty, so whichever
  # stack happens to be measured first loses. Vacuum settles all three to the
  # same steady state before any measurement.
  %w[bench_statecraft_orders bench_aasm_orders
     bench_statesman_orders bench_statesman_order_transitions].each do |seeded_table|
    ActiveRecord::Base.connection.execute("VACUUM ANALYZE #{seeded_table}")
  end
end

def print_environment_banner(script_name)
  versions = %w[statecraft aasm statesman activerecord pg benchmark-ips]
             .map { |name| "#{name} #{Gem.loaded_specs[name]&.version}" }.join(", ")
  postgres = ActiveRecord::Base.connection.select_value("SHOW server_version")
  puts "== #{script_name} #{SMOKE ? "(smoke)" : "(full)"} =="
  puts "ruby #{RUBY_VERSION} · postgres #{postgres} · #{Time.current.utc.strftime("%Y-%m-%d")}"
  puts versions
  puts "rows: #{ROW_COUNT} · threads: #{THREAD_COUNT}"
  puts
end

def ips_options
  SMOKE ? { time: 0.3, warmup: 0.1 } : { time: 5, warmup: 2 }
end
