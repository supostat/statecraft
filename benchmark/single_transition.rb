# frozen_string_literal: true

# The cost of one uncontended transition, measured as a pay/reset round
# trip on a single record. statecraft pays a savepoint + CAS UPDATE + log
# INSERT; aasm does one UPDATE; statesman INSERTs a transition and flips
# most_recent. The gap is the price of the audit log and conflict safety.
require_relative "environment"

print_environment_banner("single_transition")

statecraft_order = StatecraftOrder.create!
aasm_order = AasmOrder.create!
statesman_order = StatesmanOrder.create!

Benchmark.ips do |bench|
  bench.config(**ips_options)

  bench.report("statecraft: pay!/reset! round trip") do
    statecraft_order.pay!(metadata: {})
    statecraft_order.reset!(metadata: {})
  end

  bench.report("aasm:       pay!/reset! round trip") do
    aasm_order.pay!
    aasm_order.reset!
  end

  bench.report("statesman:  transition_to! round trip") do
    machine = statesman_order.state_machine
    machine.transition_to!(:paid)
    machine.transition_to!(:pending)
  end

  bench.compare!
end
