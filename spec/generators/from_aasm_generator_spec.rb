# frozen_string_literal: true

require "tmpdir"
require "rails/generators"
require "generators/statecraft/from_aasm/from_aasm_generator"

# The door is exercised against duck-typed aasm reflection: the shapes the
# live probe recorded (aasm 5.5.2) — states answering .name, transitions
# answering .from/.to/.opts, one transition per from even when the DSL wrote
# an array — without making aasm a development dependency of the gem.
RSpec.describe "statecraft:from_aasm generator" do
  def state_stub(name)
    Struct.new(:name).new(name)
  end

  def transition_stub(from, to, options = {})
    Struct.new(:from, :to, :opts).new(from, to, { from: from, to: to }.merge(options))
  end

  def event_stub(name, transitions)
    Struct.new(:name, :transitions, :options).new(name, transitions, {})
  end

  def aasm_machine_stub(states: %i[pending paid cancelled], initial: :pending, column: :state, events: nil)
    event_list = events || [
      event_stub(:pay, [transition_stub(:pending, :paid, guard: :payable?)]),
      event_stub(:cancel, [transition_stub(:pending, :cancelled, unless: :locked?),
                           transition_stub(:paid, :cancelled)])
    ]
    state_objects = states.map { |name| state_stub(name) }

    Struct.new(:states, :initial_state, :events, :attribute_name)
          .new(state_objects, initial, event_list, column)
  end

  def model_stub(machine, named: {})
    Class.new do
      define_singleton_method(:aasm) { |name = nil| name ? named.fetch(name) : machine }
      define_singleton_method(:table_name) { "orders" }
      define_singleton_method(:name) { "Order" }
    end
  end

  def run_generator(arguments, destination)
    Statecraft::Generators::FromAasmGenerator.start(
      arguments + ["--quiet"], destination_root: destination
    )
  end

  def build_generator(arguments, destination)
    Statecraft::Generators::FromAasmGenerator.new(
      arguments, ["--quiet"], destination_root: destination
    )
  end

  def within_tmp(&block)
    Dir.mktmpdir("statecraft-from-aasm", &block)
  end

  describe "a conventional aasm setup" do
    it "carries the events, the guards and the column into the skeleton and mounting" do
      stub_const("Order", model_stub(aasm_machine_stub))

      within_tmp do |tmp|
        FileUtils.mkdir_p(File.join(tmp, "app/models"))
        File.write(File.join(tmp, "app/models/order.rb"), "class Order < ApplicationRecord\nend\n")

        run_generator(["Order"], tmp)

        skeleton = File.read(File.join(tmp, "app/state_machines/order_flow.rb"))
        expect(skeleton).to include("class OrderFlow < ApplicationMachine")
        expect(skeleton).to include("state :pending, initial: true")
        expect(skeleton).to include("event :pay, from: :pending, to: :paid, record_guard: :payable?")
        expect(skeleton).to include("event :cancel, from: :pending, to: :cancelled, record_guard: :not_locked?")
        expect(skeleton).to include("event :cancel, from: :paid, to: :cancelled\n")
        expect(skeleton).to include("def payable?(record) = record.payable?")
        expect(skeleton).to include("def not_locked?(record) = !record.locked?")

        model = File.read(File.join(tmp, "app/models/order.rb"))
        expect(model).to include("state_machine OrderFlow, changed_at: true, helpers: true, scopes: true")
      end
    end

    it "writes one migration: the log table plus an index on the existing column" do
      stub_const("Order", model_stub(aasm_machine_stub))

      within_tmp do |tmp|
        run_generator(["Order"], tmp)

        migrations = Dir[File.join(tmp, "db/migrate/*.rb")]
        expect(migrations.size).to eq(1)
        expect(File.basename(migrations.first)).to end_with("_create_order_transitions.rb")

        source = File.read(migrations.first)
        expect(source).to include("create_table :order_transitions")
        expect(source).to include("on_delete: :cascade")
        expect(source).to include("t.index %i[order_id id]")
        expect(source).to include("add_index :orders, :state unless index_exists?(:orders, :state)")
        expect(source).to include("CHECK (state IN ('pending', 'paid', 'cancelled')) NOT VALID")
        expect(source).not_to include("add_column :orders, :state,")
        expect(source).not_to include("disable_ddl_transaction!")
        expect(source).not_to include("BATCH_SIZE")
      end
    end

    it "produces a skeleton the real compiler accepts" do
      stub_const("Order", model_stub(aasm_machine_stub))

      within_tmp do |tmp|
        run_generator(["Order"], tmp)

        load File.join(tmp, "app/state_machines/application_machine.rb")
        load File.join(tmp, "app/state_machines/order_flow.rb")

        expect(OrderFlow.states).to eq(%i[pending paid cancelled])
        expect(OrderFlow.initial_state).to eq(:pending)
        expect(OrderFlow.events).to eq(%i[pay cancel])
        expect(OrderFlow.transitions_from(:pending).map { |edge| edge[:to] }).to eq(%i[paid cancelled])
      ensure
        Object.send(:remove_const, :OrderFlow) if defined?(OrderFlow)
        Object.send(:remove_const, :ApplicationMachine) if defined?(ApplicationMachine)
      end
    end

    it "carries a non-default aasm column into the mounting line" do
      stub_const("Order", model_stub(aasm_machine_stub(column: :status)))

      within_tmp do |tmp|
        FileUtils.mkdir_p(File.join(tmp, "app/models"))
        File.write(File.join(tmp, "app/models/order.rb"), "class Order < ApplicationRecord\nend\n")

        run_generator(["Order"], tmp)

        model = File.read(File.join(tmp, "app/models/order.rb"))
        expect(model).to include("state_machine OrderFlow, column: :status, changed_at: true")

        migration = File.read(Dir[File.join(tmp, "db/migrate/*_create_order_transitions.rb")].first)
        expect(migration).to include("add_index :orders, :status unless index_exists?(:orders, :status)")
      end
    end

    it "reports a lambda guard as a TODO instead of pretending to move it" do
      lambda_guard = ->(record) { record.fine? }
      machine = aasm_machine_stub(
        events: [event_stub(:pay, [transition_stub(:pending, :paid, guard: lambda_guard)])]
      )
      stub_const("Order", model_stub(machine))

      within_tmp do |tmp|
        run_generator(["Order"], tmp)

        skeleton = File.read(File.join(tmp, "app/state_machines/order_flow.rb"))
        expect(skeleton).to include("event :pay, from: :pending, to: :paid\n")
        expect(skeleton).to include("TODO(guard): pay (pending -> paid) — defined at")
        expect(skeleton).not_to match(/^\s*event .*record_guard:/)
        expect(skeleton).not_to include("private")
      end
    end

    it "reads a named machine when asked for one" do
      shipment = aasm_machine_stub(
        states: %i[unshipped shipped], initial: :unshipped, column: :shipment_state,
        events: [event_stub(:ship, [transition_stub(:unshipped, :shipped)])]
      )
      stub_const("Order", model_stub(aasm_machine_stub, named: { shipment: shipment }))

      within_tmp do |tmp|
        run_generator(%w[Order shipment], tmp)

        skeleton = File.read(File.join(tmp, "app/state_machines/order_flow.rb"))
        expect(skeleton).to include("aasm machine shipment")
        expect(skeleton).to include("state :unshipped, initial: true")
        expect(skeleton).to include("event :ship, from: :unshipped, to: :shipped")
      end
    end
  end

  describe "refusals" do
    it "refuses a model that cannot be found" do
      within_tmp do |tmp|
        expect { build_generator(["Ghost"], tmp).invoke_all }
          .to raise_error(Thor::Error, /model class Ghost not found/)
      end
    end

    it "refuses a model that does not include AASM" do
      stub_const("Order", Class.new)

      within_tmp do |tmp|
        expect { build_generator(["Order"], tmp).invoke_all }
          .to raise_error(Thor::Error, /does not respond to \.aasm/)
      end
    end

    it "refuses an object that does not quack like an aasm machine" do
      stub_const("Order", model_stub(Object.new))

      within_tmp do |tmp|
        expect { build_generator(["Order"], tmp).invoke_all }
          .to raise_error(Thor::Error, /does not look like an aasm machine/)
      end
    end

    # The trap the live probe found: a model with named machines answers the
    # unnamed .aasm with the :default machine, which holds no states at all.
    it "refuses an empty graph and names the machines the model does declare" do
      empty = aasm_machine_stub(states: [], events: [])
      stub_const("Order", model_stub(empty))
      store = Struct.new(:machine_names).new(%w[shipment payment default])
      stub_const("AASM::StateMachineStore", Class.new { define_singleton_method(:fetch) { |_model| store } })

      within_tmp do |tmp|
        expect { build_generator(["Order"], tmp).invoke_all }
          .to raise_error(Thor::Error, /declares no states.*named machines: shipment, payment/m)
      end
    end

    it "refuses an event branching from one state and names the fix" do
      branching = aasm_machine_stub(
        events: [event_stub(:pay, [transition_stub(:pending, :paid, guard: :payable?),
                                   transition_stub(:pending, :cancelled)])]
      )
      stub_const("Order", model_stub(branching))

      within_tmp do |tmp|
        expect { build_generator(["Order"], tmp).invoke_all }
          .to raise_error(Thor::Error, /pay \(from pending\).*partial function.*fail_payment/m)
      end
    end
  end
end
