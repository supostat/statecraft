# frozen_string_literal: true

require "tmpdir"
require "rails/generators"
require "generators/statecraft/from_statesman/from_statesman_generator"

RSpec.describe "statecraft:from_statesman generator" do
  def guard_stub(from, to)
    Struct.new(:from, :to, :callback).new(from, to, proc { true })
  end

  def statesman_machine_fixture(initial: "pending", successors: nil, guards: nil)
    states_list = %w[pending paid cancelled]
    edges = successors || { "pending" => %w[paid cancelled paid] }
    guard_list = guards || [guard_stub("pending", ["paid"])]

    Class.new do
      define_singleton_method(:states) { states_list }
      define_singleton_method(:initial_state) { initial }
      define_singleton_method(:successors) { edges }
      define_singleton_method(:callbacks) { { guards: guard_list } }
    end
  end

  def run_generator(arguments, destination)
    Statecraft::Generators::FromStatesmanGenerator.start(
      arguments + ["--quiet"], destination_root: destination
    )
  end

  def build_generator(arguments, destination)
    Statecraft::Generators::FromStatesmanGenerator.new(
      arguments, ["--quiet"], destination_root: destination
    )
  end

  def within_tmp(&block)
    Dir.mktmpdir("statecraft-from-statesman", &block)
  end

  describe "a conventional statesman setup" do
    it "generates the skeleton, mounts the model and writes the conversion migration" do
      stub_const("OrderStateMachine", statesman_machine_fixture)

      within_tmp do |tmp|
        FileUtils.mkdir_p(File.join(tmp, "app/models"))
        File.write(File.join(tmp, "app/models/order.rb"), "class Order < ApplicationRecord\nend\n")

        run_generator(["Order"], tmp)

        skeleton = File.read(File.join(tmp, "app/state_machines/order_flow.rb"))
        expect(skeleton).to include("class OrderFlow < ApplicationMachine")
        expect(skeleton).to include("state :pending, initial: true")
        expect(skeleton).to include("transition from: :pending, to: :paid")
        expect(skeleton).to include("TODO(guard): pending -> paid (defined at")
        expect(skeleton).not_to match(/^\s*event :/)

        model = File.read(File.join(tmp, "app/models/order.rb"))
        expect(model).to include("state_machine OrderFlow, changed_at: true, helpers: true, scopes: true")

        migration = Dir[File.join(tmp, "db/migrate/*_convert_order_transitions_to_statecraft.rb")].first
        expect(migration).not_to be_nil
        migration_source = File.read(migration)
        expect(migration_source).to include("LAG(to_state) OVER")
        expect(migration_source).to include("ORDER BY t.sort_key DESC LIMIT 1")
        expect(migration_source).to include("add_column :orders, :state_changed_at, :datetime")
        expect(migration_source).to include("SET state_changed_at =")
        expect(migration_source).to include("COALESCE(prev.prev_state, 'pending')")
        expect(migration_source).to include("on_delete: :cascade")
        expect(migration_source).to include("state IN ('pending', 'paid', 'cancelled')")
        expect(migration_source).to include("remove_column :order_transitions, :sort_key")
        expect(migration_source).to include("add_index :order_transitions, %i[order_id id]")
      end
    end

    it "produces a skeleton the real compiler accepts, with statesman's duplicate edges deduplicated" do
      stub_const("OrderStateMachine", statesman_machine_fixture)

      within_tmp do |tmp|
        run_generator(["Order"], tmp)

        load File.join(tmp, "app/state_machines/application_machine.rb")
        load File.join(tmp, "app/state_machines/order_flow.rb")

        expect(OrderFlow.states).to eq(%i[pending paid cancelled])
        expect(OrderFlow.initial_state).to eq(:pending)
        expect(OrderFlow.transitions_from(:pending).map { |edge| edge[:to] }).to eq(%i[paid cancelled])
      ensure
        Object.send(:remove_const, :OrderFlow) if defined?(OrderFlow)
        Object.send(:remove_const, :ApplicationMachine) if defined?(ApplicationMachine)
      end
    end

    it "honors an explicit statesman machine class name" do
      stub_const("BillingMachine", statesman_machine_fixture)

      within_tmp do |tmp|
        run_generator(%w[Order BillingMachine], tmp)

        expect(File).to exist(File.join(tmp, "app/state_machines/order_flow.rb"))
        skeleton = File.read(File.join(tmp, "app/state_machines/order_flow.rb"))
        expect(skeleton).to include("Skeleton generated from BillingMachine")
      end
    end
  end

  describe "refusals" do
    it "refuses when the statesman machine class cannot be found" do
      within_tmp do |tmp|
        expect { build_generator(["Order"], tmp).invoke_all }
          .to raise_error(Thor::Error, /OrderStateMachine not found/)
      end
    end

    it "refuses a class that does not quack like a statesman machine" do
      stub_const("OrderStateMachine", Class.new)

      within_tmp do |tmp|
        expect { build_generator(["Order"], tmp).invoke_all }
          .to raise_error(Thor::Error, /does not look like a statesman machine/)
      end
    end

    it "refuses a machine with no initial state" do
      stub_const("OrderStateMachine", statesman_machine_fixture(initial: nil))

      within_tmp do |tmp|
        expect { build_generator(["Order"], tmp).invoke_all }
          .to raise_error(Thor::Error, /no initial state/)
      end
    end
  end
end
