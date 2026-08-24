# frozen_string_literal: true

require "English"
require "support/test_schema"

RSpec.describe "mounting" do
  before { TestSchema.load! }

  def define_flow(&extra)
    stub_const("OrderFlow", Class.new do
      include Statecraft::Machine

      state :pending, initial: true
      state :paid
      event :pay, from: :pending, to: :paid
      class_eval(&extra) if extra
    end)
  end

  def define_order(&body)
    stub_const("Order", Class.new(ActiveRecord::Base) do
      self.table_name = "orders"
      class_eval(&body) if body
    end)
  end

  def define_order_log
    stub_const("OrderTransition", Class.new(ActiveRecord::Base) do
      self.table_name = "order_transitions"
    end)
  end

  describe "the kwargs signature and defaults" do
    it "resolves the log class by the <Model>Transition convention" do
      define_flow
      define_order
      define_order_log
      configuration = Order.state_machine(OrderFlow)
      expect(configuration.log_class).to eq(OrderTransition)
    end

    it "honors an explicit log: override" do
      define_flow
      define_order
      stub_const("PaymentAudit", Class.new(ActiveRecord::Base) { self.table_name = "order_transitions" })
      configuration = Order.state_machine(OrderFlow, log: PaymentAudit)
      expect(configuration.log_class).to eq(PaymentAudit)
    end

    it "defaults column to :state, touch to true, flags to false, changed_at to off" do
      define_flow
      define_order
      define_order_log
      configuration = Order.state_machine(OrderFlow)
      expect(configuration.column).to eq(:state)
      expect(configuration.touch).to be(true)
      expect(configuration.helpers).to be(false)
      expect(configuration.scopes).to be(false)
      expect(configuration.changed_at_column).to be_nil
    end

    it "derives changed_at column name from column: when changed_at: true" do
      define_flow
      define_order
      define_order_log
      configuration = Order.state_machine(OrderFlow, column: :status, changed_at: true)
      expect(configuration.changed_at_column).to eq(:status_changed_at)
    end

    it "takes an explicit changed_at: symbol as the column name" do
      define_flow
      define_order
      define_order_log
      configuration = Order.state_machine(OrderFlow, changed_at: :flipped_at)
      expect(configuration.changed_at_column).to eq(:flipped_at)
    end

    it "records touch: false" do
      define_flow
      define_order
      define_order_log
      configuration = Order.state_machine(OrderFlow, touch: false)
      expect(configuration.touch).to be(false)
    end

    it "fails with a hint when the conventional log class is missing" do
      define_flow
      define_order
      expect { Order.state_machine(OrderFlow) }
        .to raise_error(Statecraft::CompilationError, /OrderTransition not found.*pass log:/)
    end
  end

  describe "mounting checks" do
    it "raises AlreadyMounted on a second mount" do
      define_flow
      define_order
      define_order_log
      Order.state_machine(OrderFlow)
      expect { Order.state_machine(OrderFlow) }.to raise_error(Statecraft::AlreadyMounted, /already carries/)
    end

    it "raises AlreadyMounted when an STI subclass mounts again" do
      define_flow
      define_order
      define_order_log
      Order.state_machine(OrderFlow)
      stub_const("CreditOrder", Class.new(Order))
      expect { CreditOrder.state_machine(OrderFlow) }
        .to raise_error(Statecraft::AlreadyMounted, /inheritance shares the base machine/)
    end

    it "mounts with every option on and no database connection (isolated process)" do
      probe = <<~RUBY
        require "statecraft"

        class OrderFlow
          include Statecraft::Machine

          state :pending, initial: true
          state :paid
          event :pay, from: :pending, to: :paid
        end

        class OrderTransition < ActiveRecord::Base; end

        class Order < ActiveRecord::Base
          state_machine OrderFlow, changed_at: true, helpers: true, scopes: true
        end

        abort("mounting did not store the configuration") unless Order.statecraft_mounting
      RUBY

      output = IO.popen([RbConfig.ruby, "-Ilib", "-e", probe], err: %i[child out], &:read)
      expect($CHILD_STATUS).to be_success, "mounting needs a live connection: #{output}"
    end

    it "raises ConnectionMismatch when the log lives on a foreign connection class" do
      define_flow
      define_order
      stub_const("OtherBase", Class.new(ActiveRecord::Base) { self.abstract_class = true })
      OtherBase.establish_connection(adapter: "sqlite3", database: ":memory:")
      stub_const("OrderTransition", Class.new(OtherBase) { self.table_name = "order_transitions" })
      expect { Order.state_machine(OrderFlow) }
        .to raise_error(Statecraft::ConnectionMismatch, /does not share/)
    end
  end

  describe "name conflicts at finalization" do
    it "rejects an event named after the gem's own mounted surface" do
      define_flow { event :fire, from: :pending, to: :paid }
      define_order
      define_order_log
      expect { Order.state_machine(OrderFlow, helpers: true) }
        .to raise_error(Statecraft::CompilationError, /statecraft itself mounts/)
    end

    it "rejects a verb clashing with an instance method when helpers: true" do
      define_flow
      define_order do
        def pay = :existing
      end
      define_order_log
      expect { Order.state_machine(OrderFlow, helpers: true) }
        .to raise_error(Statecraft::CompilationError, /helper pay for event :pay conflicts/)
    end

    it "ignores verb clashes when helpers stay off" do
      define_flow
      define_order do
        def pay = :existing
      end
      define_order_log
      expect { Order.state_machine(OrderFlow) }.not_to raise_error
    end

    it "rejects a scope clashing with a class method when scopes: true" do
      define_flow
      define_order do
        def self.pending = :existing
      end
      define_order_log
      expect { Order.state_machine(OrderFlow, scopes: true) }
        .to raise_error(Statecraft::CompilationError, /scope pending conflicts/)
    end
  end
end
