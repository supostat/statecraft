# frozen_string_literal: true

# Concurrent writers: THREAD_COUNT threads race one pending record through
# the same transition. The table of outcomes is the result — successes,
# error classes, log rows written, callbacks fired. Correctness, not speed.
require_relative "environment"

print_environment_banner("concurrent_write")

def race(threads:)
  barrier = Queue.new
  workers = Array.new(threads) do
    Thread.new do
      barrier.pop
      yield
    end
  end
  sleep 0.05 until workers.all? { |thread| thread.status == "sleep" }
  threads.times { barrier.push(nil) }
  workers.each(&:join)
end

def report(gem_name, attempts:, successes:, errors:, log_rows:, final_state:)
  puts format("%-11s attempts %d · successes %d · callbacks %d · log rows %d · final %s",
              gem_name, attempts, successes, CALLBACK_COUNTER.count, log_rows, final_state)
  errors.tally.each { |error_class, count| puts "            #{count} × #{error_class}" }
  lost_updates = successes - 1
  puts "            lost updates: #{lost_updates} (#{lost_updates.zero? ? "none" : "state overwritten silently"})" if errors.empty?
  puts
end

# --- statecraft ---------------------------------------------------------

CALLBACK_COUNTER.reset
order = StatecraftOrder.create!
successes = 0
errors = []
mutex = Mutex.new

race(threads: THREAD_COUNT) do
  StatecraftOrder.find(order.id).pay!(metadata: {})
  mutex.synchronize { successes += 1 }
rescue Statecraft::TransitionConflict => error
  mutex.synchronize { errors << error.class.name }
end

report("statecraft:",
       attempts: THREAD_COUNT, successes: successes, errors: errors,
       log_rows: StatecraftOrderTransition.where(statecraft_order_id: order.id).count,
       final_state: order.reload[:state])

# --- aasm ---------------------------------------------------------------

CALLBACK_COUNTER.reset
order = AasmOrder.create!
successes = 0
errors = []

race(threads: THREAD_COUNT) do
  record = AasmOrder.find(order.id)
  record.pay! if record.may_pay?
  mutex.synchronize { successes += 1 }
rescue AASM::InvalidTransition => error
  mutex.synchronize { errors << error.class.name }
end

report("aasm:",
       attempts: THREAD_COUNT, successes: successes, errors: errors,
       log_rows: 0,
       final_state: order.reload.state)

# --- statesman ----------------------------------------------------------

CALLBACK_COUNTER.reset
order = StatesmanOrder.create!
successes = 0
errors = []

race(threads: THREAD_COUNT) do
  StatesmanOrder.find(order.id).state_machine.transition_to!(:paid)
  mutex.synchronize { successes += 1 }
rescue ActiveRecord::RecordNotUnique, Statesman::TransitionConflictError => error
  mutex.synchronize { errors << error.class.name }
end

report("statesman:",
       attempts: THREAD_COUNT, successes: successes, errors: errors,
       log_rows: StatesmanOrderTransition.where(bench_statesman_order_id: order.id).count,
       final_state: StatesmanOrder.find(order.id).state_machine.current_state)
