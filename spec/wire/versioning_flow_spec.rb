# frozen_string_literal: true

require "tmpdir"
require "rails/generators"
require "generators/statecraft/machine/machine_generator"

# The versioning feature end to end on generated shapes: the --versioning
# migration really executes, the generated mounting line really mounts, and
# a live seen: token passes, goes stale, and loses an ABA race — through
# the real pipeline, no mocks.
RSpec.describe "wire: versioning end to end" do
  it "executes the generated migration and catches live staleness" do
    Dir.mktmpdir("statecraft-versioning-wire") do |tmp|
      Statecraft::Generators::MachineGenerator.start(
        ["Order", "--versioning", "--quiet"], destination_root: tmp
      )
      migration_path = Dir[File.join(tmp, "db/migrate/*_create_order_state_machine.rb")].first
      expect(migration_path).not_to be_nil

      ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
      ActiveRecord::Migration.verbose = false
      load migration_path
      CreateOrderStateMachine.new.migrate(:up)

      connection = ActiveRecord::Base.connection
      expect(connection.columns(:orders).map(&:name)).to include("state_version")
      connection.remove_check_constraint :orders, name: "orders_state_check"
      connection.add_check_constraint :orders, "state IN ('pending', 'paid', 'cancelled')",
                                      name: "orders_state_check"

      stub_const("ApplicationRecord", Class.new(ActiveRecord::Base) { self.abstract_class = true })
      load File.join(tmp, "app/state_machines/application_machine.rb")
      load File.join(tmp, "app/models/order_transition.rb")
      stub_const("OrderFlow", Class.new(ApplicationMachine) do
        state :pending, initial: true
        state :paid
        state :cancelled

        event :pay, from: :pending, to: :paid
        transition from: :pending, to: :cancelled
        transition from: :paid, to: :cancelled
        transition from: :paid, to: :pending
      end)
      # The generated model carries the generated mounting line —
      # versioning: true included — so loading it proves that line works.
      load File.join(tmp, "app/models/order.rb")
      expect(Order.statecraft_mounting.version_column).to eq(:state_version)

      # A live transition with the freshly rendered token, via the helper verb.
      order = Order.create!
      expect(order[:state_version]).to eq(0)
      order.pay!(seen: order[:state_version])
      expect(order[:state_version]).to eq(1)

      # The same token again is a stale snapshot: the 409 material.
      expect { order.transition_to!(:cancelled, seen: 0) }
        .to raise_error(Statecraft::StaleTransition)

      # ABA without a token: the state comes back, the version does not.
      Order.where(id: order.id).update_all(state: "pending", state_version: 5)
      stale_read = Order.find(order.id)
      Order.where(id: order.id).update_all(state: "paid", state_version: 6)
      Order.where(id: order.id).update_all(state: "pending", state_version: 7)
      expect { stale_read.transition_to!(:cancelled) }
        .to raise_error(Statecraft::TransitionConflict)

      # A fresh read carries the current version and passes again.
      current = Order.find(order.id)
      expect(current.transition_to!(:cancelled, seen: current[:state_version]))
        .to be_a(OrderTransition)
    ensure
      %i[CreateOrderStateMachine ApplicationMachine OrderTransition Order].each do |loaded_constant|
        Object.send(:remove_const, loaded_constant) if Object.const_defined?(loaded_constant)
      end
      SpecDatabase.connect!
    end
  end
end
