# frozen_string_literal: true

require "tmpdir"
require "rails/generators"
require "generators/statecraft/machine/machine_generator"

RSpec.describe "wire: the main path end to end" do
  it "runs the full lifecycle on real modules from generated schema to CASCADE" do
    Dir.mktmpdir("statecraft-wire") do |tmp|
      # 1. The schema comes from the generator's own templates.
      Statecraft::Generators::MachineGenerator.start(["Order", "--quiet"], destination_root: tmp)
      migration_path = Dir[File.join(tmp, "db/migrate/*_create_order_state_machine.rb")].first
      expect(migration_path).not_to be_nil

      ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
      ActiveRecord::Migration.verbose = false
      load migration_path
      CreateOrderStateMachine.new.migrate(:up)

      # Widen the generated CHECK for the scenario's states — the documented
      # recipe: dropping and re-adding the constraint is cheap in one step.
      connection = ActiveRecord::Base.connection
      connection.remove_check_constraint :orders, name: "orders_state_check"
      connection.add_check_constraint(
        :orders, "state IN ('pending', 'paid', 'fulfilled', 'cancelled')",
        name: "orders_state_check"
      )

      # 2. Real machine, real log model, real mounting — generated shapes.
      stub_const("ApplicationRecord", Class.new(ActiveRecord::Base) { self.abstract_class = true })
      load File.join(tmp, "app/state_machines/application_machine.rb")
      load File.join(tmp, "app/models/order_transition.rb")

      commit_probe = []
      stub_const("OrderFlow", Class.new(ApplicationMachine) do
        state :pending, initial: true
        state :paid
        state :fulfilled
        state :cancelled

        event :pay, from: :pending, to: :paid, guard: :payable?
        event :fulfill, from: :paid, to: :fulfilled
        transition from: :pending, to: :cancelled

        after_transition ->(record, _transition) { record.fire!(:fulfill) }, event: [:pay]
        after_commit ->(_record, transition) { commit_probe << transition.event }

        private

        def payable?(_record, metadata)
          metadata["amount"].to_i.positive?
        end
      end)
      stub_const("Order", Class.new(ActiveRecord::Base) do
        self.table_name = "orders"
      end)
      Order.state_machine(OrderFlow, changed_at: true, helpers: true, scopes: true)

      # 3. Birth by column default; the log is silent about it.
      order = Order.create!
      expect(order.in_state?(:pending)).to be(true)
      expect(Order.pending.count).to eq(1)
      expect(order.history).to be_empty
      expect(order.transitioned_to?(:pending)).to be(false)

      # 4. Guards refuse, nothing is written.
      expect(order.pay(metadata: { amount: 0 })).to be(false)
      expect(order.history).to be_empty

      # 5. A real transition with metadata launches the chain.
      log_record = order.pay!(metadata: { amount: 100, reason: :gift })
      expect(log_record.metadata).to eq({ "amount" => 100, "reason" => "gift" })
      expect(order.reload.state).to eq("fulfilled")
      expect(order.history.map(&:event)).to eq(%w[pay fulfill])
      expect(order.state_changed_at).not_to be_nil
      expect(commit_probe).to eq(%i[fulfill pay])

      # 6. Introspection over the fresh state.
      expect(order.available_events).to eq([])
      expect(order.available_transitions).to eq([])
      expect(order.transitioned_to?(:paid)).to be(true)

      # 7. Bypass on a sibling record: event guards skipped, event: nil logged.
      sibling = Order.create!
      bypass_row = sibling.transition_to!(:paid, bypass_events: true, metadata: { amount: 0 })
      expect(bypass_row.event).to be_nil

      # 8. The log is a read-model: persisted rows refuse updates.
      expect { log_record.update!(event: "tampered") }
        .to raise_error(ActiveRecord::ReadOnlyRecord)

      # 9. destroy cascades to the log at the database level.
      expect(OrderTransition.where(order_id: order.id).count).to eq(2)
      order.destroy
      expect(OrderTransition.where(order_id: order.id).count).to eq(0)
      expect(OrderTransition.where(order_id: sibling.id).count).to eq(1)
    ensure
      %i[CreateOrderStateMachine ApplicationMachine OrderTransition].each do |loaded_constant|
        Object.send(:remove_const, loaded_constant) if Object.const_defined?(loaded_constant)
      end
      SpecDatabase.connect!
    end
  end
end
