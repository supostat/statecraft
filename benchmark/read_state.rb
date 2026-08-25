# frozen_string_literal: true

# Reading the current state: statecraft and aasm answer from an indexed
# column, statesman derives it from the transition table (most_recent join).
# Two questions per stack: count all paid orders, load a page of 100.
require_relative "environment"

print_environment_banner("read_state")
seed_read_corpus

paid_count = StatecraftOrder.where(state: "paid").count
puts "corpus: #{StatecraftOrder.count} rows per stack, #{paid_count} paid"
puts

Benchmark.ips do |bench|
  bench.config(**ips_options)

  bench.report("statecraft: where(state:).count") { StatecraftOrder.where(state: "paid").count }
  bench.report("aasm:       where(state:).count") { AasmOrder.where(state: "paid").count }
  bench.report("statesman:  in_state(:paid).count") { StatesmanOrder.in_state(:paid).count }

  bench.compare!
end

Benchmark.ips do |bench|
  bench.config(**ips_options)

  bench.report("statecraft: page of 100") { StatecraftOrder.where(state: "paid").limit(100).to_a }
  bench.report("aasm:       page of 100") { AasmOrder.where(state: "paid").limit(100).to_a }
  bench.report("statesman:  page of 100") { StatesmanOrder.in_state(:paid).limit(100).to_a }

  bench.compare!
end
