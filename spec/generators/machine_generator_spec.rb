# frozen_string_literal: true

require "tmpdir"
require "rails/generators"
require "generators/statecraft/machine/machine_generator"

RSpec.describe "statecraft:machine generator" do
  def run_generator(arguments, destination)
    Statecraft::Generators::MachineGenerator.start(
      arguments + ["--quiet"], destination_root: destination
    )
  end

  def within_tmp
    Dir.mktmpdir("statecraft-generator") { |tmp| yield tmp }
  end

  describe "a fresh model" do
    it "generates the machine, log model, model, ApplicationMachine and a create migration" do
      within_tmp do |tmp|
        run_generator(["Order"], tmp)

        expect(File).to exist(File.join(tmp, "app/state_machines/application_machine.rb"))
        expect(File).to exist(File.join(tmp, "app/state_machines/order_flow.rb"))
        expect(File).to exist(File.join(tmp, "app/models/order_transition.rb"))
        expect(File).to exist(File.join(tmp, "app/models/order.rb"))

        migration = Dir[File.join(tmp, "db/migrate/*_create_order_state_machine.rb")].first
        expect(migration).not_to be_nil
        migration_source = File.read(migration)
        expect(migration_source).to include("add_check_constraint")
        expect(migration_source).to include("orders_state_check")
        expect(migration_source).to include("on_delete: :cascade")
        expect(migration_source).to include("t.index %i[order_id id]")
      end
    end

    it "loads and compiles with the real core, mounting without a database" do
      within_tmp do |tmp|
        run_generator(["Order"], tmp)
        stub_const("ApplicationRecord", Class.new(ActiveRecord::Base) { self.abstract_class = true })

        load File.join(tmp, "app/state_machines/application_machine.rb")
        load File.join(tmp, "app/state_machines/order_flow.rb")
        load File.join(tmp, "app/models/order_transition.rb")
        load File.join(tmp, "app/models/order.rb")

        expect(OrderFlow.ancestors).to include(Statecraft::Machine)
        expect(OrderFlow.states).to eq([:pending])
        expect(OrderFlow.initial_state).to eq(:pending)
        expect(Order.statecraft_mounting.log_class).to eq(OrderTransition)
        expect(Order.statecraft_mounting.helpers).to be(true)
        expect(Order.statecraft_mounting.scopes).to be(true)
        expect(Order.statecraft_mounting.changed_at_column).to eq(:state_changed_at)
        expect(OrderTransition.method_defined?(:readonly?)).to be(true)
      ensure
        %i[ApplicationMachine OrderFlow OrderTransition Order].each do |generated_constant|
          Object.send(:remove_const, generated_constant) if Object.const_defined?(generated_constant)
        end
      end
    end

    it "keeps an existing ApplicationMachine untouched" do
      within_tmp do |tmp|
        target = File.join(tmp, "app/state_machines/application_machine.rb")
        FileUtils.mkdir_p(File.dirname(target))
        File.write(target, "# custom\n")

        run_generator(["Order"], tmp)

        expect(File.read(target)).to eq("# custom\n")
      end
    end
  end

  describe "an existing model" do
    it "adds columns without a CHECK constraint and injects the mounting" do
      within_tmp do |tmp|
        model_path = File.join(tmp, "app/models/legacy_item.rb")
        FileUtils.mkdir_p(File.dirname(model_path))
        File.write(model_path, "class LegacyItem < ApplicationRecord\nend\n")

        run_generator(["LegacyItem"], tmp)

        migration = Dir[File.join(tmp, "db/migrate/*_create_legacy_item_state_machine.rb")].first
        migration_source = File.read(migration)
        expect(migration_source).to include("add_column :legacy_items, :state")
        expect(migration_source).not_to include("add_check_constraint")
        expect(migration_source).to include("NOT VALID")
        expect(migration_source).to include("on_delete: :cascade")

        expect(File.read(model_path)).to include("state_machine LegacyItemFlow")
      end
    end
  end

  describe "a namespaced model" do
    it "places every artifact by the full path and prefixes the tables" do
      within_tmp do |tmp|
        run_generator(["Shop::Order"], tmp)

        expect(File).to exist(File.join(tmp, "app/models/shop.rb"))
        expect(File).to exist(File.join(tmp, "app/state_machines/shop/order_flow.rb"))
        expect(File).to exist(File.join(tmp, "app/models/shop/order_transition.rb"))
        expect(File).to exist(File.join(tmp, "app/models/shop/order.rb"))

        namespace_module = File.read(File.join(tmp, "app/models/shop.rb"))
        expect(namespace_module).to include("module Shop")
        expect(namespace_module).to include('"shop_"')
        expect(File.read(File.join(tmp, "app/state_machines/shop/order_flow.rb")))
          .to include("class Shop::OrderFlow")
        expect(File.read(File.join(tmp, "app/models/shop/order_transition.rb")))
          .to include("class Shop::OrderTransition")

        migration = Dir[File.join(tmp, "db/migrate/*_create_shop_order_state_machine.rb")].first
        expect(migration).not_to be_nil
        migration_source = File.read(migration)
        expect(migration_source).to include("class CreateShopOrderStateMachine")
        expect(migration_source).to include("create_table :shop_orders")
        expect(migration_source).to include("create_table :shop_order_transitions")
        expect(migration_source).to include("t.references :order")
        expect(migration_source).to include("t.index %i[order_id id]")
      end
    end

    it "loads and compiles a namespaced set with the real core" do
      within_tmp do |tmp|
        run_generator(["Shop::Order"], tmp)
        stub_const("ApplicationRecord", Class.new(ActiveRecord::Base) { self.abstract_class = true })

        load File.join(tmp, "app/models/shop.rb")
        load File.join(tmp, "app/state_machines/application_machine.rb")
        load File.join(tmp, "app/state_machines/shop/order_flow.rb")
        load File.join(tmp, "app/models/shop/order_transition.rb")
        load File.join(tmp, "app/models/shop/order.rb")

        expect(Shop::Order.statecraft_mounting.log_class).to eq(Shop::OrderTransition)
        expect(Shop::Order.table_name).to eq("shop_orders")
        expect(Shop::OrderTransition.table_name).to eq("shop_order_transitions")
      ensure
        %i[ApplicationMachine Shop].each do |generated_constant|
          Object.send(:remove_const, generated_constant) if Object.const_defined?(generated_constant)
        end
      end
    end

    it "detects an existing namespaced model and injects the mounting" do
      within_tmp do |tmp|
        model_path = File.join(tmp, "app/models/shop/order.rb")
        FileUtils.mkdir_p(File.dirname(model_path))
        File.write(model_path, "module Shop\n  class Order < ApplicationRecord\n  end\nend\n")

        run_generator(["Shop::Order"], tmp)

        expect(File.read(model_path)).to include("state_machine Shop::OrderFlow")
        expect(File).not_to exist(File.join(tmp, "app/models/shop.rb"))

        migration = Dir[File.join(tmp, "db/migrate/*_create_shop_order_state_machine.rb")].first
        expect(File.read(migration)).to include("add_column")
        expect(File.read(migration)).not_to include("add_check_constraint")
      end
    end
  end

  describe "multi-database placement" do
    it "honors migrations_paths configured for the model's database" do
      within_tmp do |tmp|
        other_base = Class.new(ActiveRecord::Base) { self.abstract_class = true }
        stub_const("OrdersBase", other_base)
        OrdersBase.establish_connection(
          adapter: "sqlite3", database: ":memory:", migrations_paths: "db/orders_migrate"
        )
        stub_const("Invoice", Class.new(OrdersBase))

        model_path = File.join(tmp, "app/models/invoice.rb")
        FileUtils.mkdir_p(File.dirname(model_path))
        File.write(model_path, "class Invoice < OrdersBase\nend\n")

        run_generator(["Invoice"], tmp)

        migration = Dir[File.join(tmp, "db/orders_migrate/*_create_invoice_state_machine.rb")].first
        expect(migration).not_to be_nil
      end
    end

    it "falls back to db/migrate when the connection has no migrations_paths" do
      within_tmp do |tmp|
        other_base = Class.new(ActiveRecord::Base) { self.abstract_class = true }
        stub_const("BillingBase", other_base)
        BillingBase.establish_connection(adapter: "sqlite3", database: ":memory:")
        stub_const("Payment", Class.new(BillingBase))

        model_path = File.join(tmp, "app/models/payment.rb")
        FileUtils.mkdir_p(File.dirname(model_path))
        File.write(model_path, "class Payment < BillingBase\nend\n")

        run_generator(["Payment"], tmp)

        migration = Dir[File.join(tmp, "db/migrate/*_create_payment_state_machine.rb")].first
        expect(migration).not_to be_nil
      end
    end
  end
end
