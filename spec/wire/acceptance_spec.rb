# frozen_string_literal: true

require "support/test_schema"
require "tmpdir"
require "English"

# The consolidated acceptance checklist of the GRILL protocol. Deliberately
# overlaps the per-phase specs: this file is the acceptance walk, one example
# per protocol point, so a regression anywhere shows up here by name.
RSpec.describe "wire: protocol acceptance" do
  before do
    TestSchema.load!
    ActiveRecord::Base.connection.execute("DELETE FROM orders")
    ActiveRecord::Base.connection.execute("DELETE FROM order_transitions")
  end

  def define_standard_order(mount_options = {})
    stub_const("OrderFlow", Class.new do
      include Statecraft::Machine

      state :pending, initial: true
      state :paid
      state :cancelled

      event :pay, from: :pending, to: :paid, guard: :payable?
      transition from: :pending, to: :cancelled, guard: :edge_open?
      transition from: :paid, to: :paid

      def payable?(_record, metadata) = metadata["amount"].to_i.positive?
      def edge_open?(_record, _metadata) = true
    end)
    stub_const("Order", Class.new(ActiveRecord::Base) { self.table_name = "orders" })
    stub_const("OrderTransition", Class.new(ActiveRecord::Base) do
      self.table_name = "order_transitions"

      def readonly? = persisted?
    end)
    Order.state_machine(OrderFlow, **mount_options)
  end

  describe "1. concurrency (PostgreSQL)" do
    it "lets exactly one of N threads win; the rest get TransitionConflict; one log row" do
      skip "concurrency proof runs on PostgreSQL (CI)" unless SpecDatabase.postgres?

      define_standard_order
      order = Order.create!
      outcomes = Array.new(4)

      threads = 4.times.map do |thread_index|
        Thread.new do
          Order.connection_pool.with_connection do
            Order.find(order.id).fire!(:pay, metadata: { amount: 1 })
            outcomes[thread_index] = :success
          rescue Statecraft::TransitionConflict
            outcomes[thread_index] = :conflict
          end
        end
      end
      threads.each(&:join)

      expect(outcomes.count(:success)).to eq(1)
      expect(outcomes.count(:conflict)).to eq(3)
      expect(OrderTransition.where(order_id: order.id).count).to eq(1)
    end
  end

  describe "2. bypass policy" do
    it "refuses direct transition over an event-guarded edge; bypass logs event nil" do
      define_standard_order
      order = Order.create!
      expect { order.transition_to!(:paid) }.to raise_error(Statecraft::InvalidTransition, /bypass_events/)
      row = order.transition_to!(:paid, bypass_events: true, metadata: { amount: 0 })
      expect(row.event).to be_nil
    end
  end

  describe "3. the guard matrix" do
    it "runs edge guards on both call paths and event guards only through the event" do
      calls = []
      stub_const("MatrixFlow", Class.new do
        include Statecraft::Machine

        state :a, initial: true
        state :b
        transition from: :a, to: :b, guard: ->(_r, _m) { calls << :edge; true }
        event :go, from: :a, to: :b, guard: ->(_r, _m) { calls << :event; true }
      end)
      stub_const("Order", Class.new(ActiveRecord::Base) { self.table_name = "orders" })
      stub_const("OrderTransition", Class.new(ActiveRecord::Base) { self.table_name = "order_transitions" })
      Order.state_machine(MatrixFlow)

      Order.create!(state: "a").fire!(:go)
      expect(calls).to eq(%i[edge event])

      calls.clear
      Order.create!(state: "a").transition_to!(:b, bypass_events: true)
      expect(calls).to eq(%i[edge])
    end
  end

  describe "4. loops" do
    it "passes a from == to loop through CAS with a log row" do
      define_standard_order
      order = Order.create!(state: "paid")
      expect(order.transition_to!(:paid).to_state).to eq("paid")
      expect(order.history.count).to eq(1)
    end
  end

  describe "5. initial state" do
    it "finds a never-transitioned record via where(state: initial) with no special logic" do
      define_standard_order
      order = Order.create!
      expect(Order.where(state: "pending")).to include(order)
      expect(order.history).to be_empty
    end
  end

  describe "6. in_state equivalent" do
    it "is a plain where on the column: zero joins in SQL" do
      define_standard_order(scopes: true)
      sql = Order.pending.to_sql
      expect(sql.downcase).not_to include("join")
      expect(sql).to include(%("orders"."state"))
    end
  end

  describe "7. compilation catches" do
    def machine(&body)
      Class.new do
        include Statecraft::Machine

        class_eval(&body)
      end
    end

    it "unknown state, two initials, duplicate pair, duplicate from, empty event" do
      expect { machine { state :a, initial: true; transition from: :a, to: :ghost }.finalize! }
        .to raise_error(Statecraft::CompilationError, /unknown state/)
      expect { machine { state :a, initial: true; state :b, initial: true }.finalize! }
        .to raise_error(Statecraft::CompilationError, /exactly one initial/)
      expect { machine { state :a, initial: true; state :b; transition from: :a, to: :b; transition from: :a, to: :b }.finalize! }
        .to raise_error(Statecraft::CompilationError, /duplicate edge/)
      expect { machine { state :a, initial: true; state :b; state :c; event(:go) { transition from: :a, to: :b; transition from: :a, to: :c } }.finalize! }
        .to raise_error(Statecraft::CompilationError, /two edges from/)
      expect { machine { state :a, initial: true; event(:hollow) {} }.finalize! } # rubocop:disable Lint/EmptyBlock
        .to raise_error(Statecraft::CompilationError, /no edges/)
    end

    it "helper and scope name conflicts" do
      define_standard_order
      stub_const("ClashOrder", Class.new(ActiveRecord::Base) do
        self.table_name = "orders"

        def pay = :existing
        def self.pending = :existing
      end)
      expect { ClashOrder.state_machine(OrderFlow, log: OrderTransition, helpers: true) }
        .to raise_error(Statecraft::CompilationError, /helper pay/)
      stub_const("ClashOrder2", Class.new(ActiveRecord::Base) do
        self.table_name = "orders"

        def self.pending = :existing
      end)
      expect { ClashOrder2.state_machine(OrderFlow, log: OrderTransition, scopes: true) }
        .to raise_error(Statecraft::CompilationError, /scope pending/)
    end
  end

  describe "8-9. re-entrancy and chains" do
    it "raises NestedTransitionError from before/guard; chains log per hop with inverted FIFO; depth 17 dies" do
      commit_order = []
      stub_const("ChainFlow", Class.new do
        include Statecraft::Machine

        state :pending, initial: true
        state :paid
        state :fulfilled
        event :pay, from: :pending, to: :paid
        event :fulfill, from: :paid, to: :fulfilled
        after_transition ->(record, _t) { record.fire!(:fulfill) }, event: [:pay]
        after_commit ->(_r, transition) { commit_order << transition.event }
      end)
      stub_const("Order", Class.new(ActiveRecord::Base) { self.table_name = "orders" })
      stub_const("OrderTransition", Class.new(ActiveRecord::Base) { self.table_name = "order_transitions" })
      Order.state_machine(ChainFlow)

      order = Order.create!
      order.fire!(:pay)
      expect(order.history.map(&:event)).to eq(%w[pay fulfill])
      expect(commit_order).to eq(%i[fulfill pay])

      stub_const("NestedFlow", Class.new do
        include Statecraft::Machine

        state :pending, initial: true
        state :paid
        state :cancelled
        event :pay, from: :pending, to: :paid
        transition from: :pending, to: :cancelled
        before_transition ->(record, _t) { record.transition_to!(:cancelled) }, event: [:pay]
      end)
      stub_const("Order", Class.new(ActiveRecord::Base) { self.table_name = "orders" })
      Order.state_machine(NestedFlow, log: OrderTransition)
      expect { Order.create!.fire!(:pay) }.to raise_error(Statecraft::NestedTransitionError)

      stub_const("PingFlow", Class.new do
        include Statecraft::Machine

        state :ping, initial: true
        state :pong
        event :hit, from: :ping, to: :pong
        event :back, from: :pong, to: :ping
        after_transition ->(record, transition) { record.fire!(transition.to == :pong ? :back : :hit) }
      end)
      stub_const("Order", Class.new(ActiveRecord::Base) { self.table_name = "orders" })
      Order.state_machine(PingFlow, log: OrderTransition)
      expect { Order.create!(state: "ping").fire!(:hit) }
        .to raise_error(Statecraft::ChainDepthExceeded) { |error| expect(error.chain.length).to eq(17) }
    end
  end

  describe "10. savepoint transaction scenarios" do
    it "rescued conflict keeps outer work; outer rollback kills transition and after_commit; create+transition works" do
      committed = []
      stub_const("TxFlow", Class.new do
        include Statecraft::Machine

        state :pending, initial: true
        state :paid
        event :pay, from: :pending, to: :paid
        after_commit ->(_r, t) { committed << t.to }
      end)
      stub_const("Order", Class.new(ActiveRecord::Base) { self.table_name = "orders" })
      stub_const("OrderTransition", Class.new(ActiveRecord::Base) { self.table_name = "order_transitions" })
      Order.state_machine(TxFlow)

      order = Order.create!
      sibling = Order.create!
      Order.where(id: order.id).update_all(state: "paid")
      Order.transaction do
        sibling.update!(status: "outer")
        begin
          order.fire!(:pay)
        rescue Statecraft::TransitionConflict
          nil
        end
      end
      expect(sibling.reload.status).to eq("outer")

      rolled = Order.create!
      Order.transaction do
        rolled.fire!(:pay)
        raise ActiveRecord::Rollback
      end
      expect(rolled.reload.state).to eq("pending")
      expect(committed).to be_empty

      created = nil
      Order.transaction do
        created = Order.create!
        created.fire!(:pay)
      end
      expect(created.reload.state).to eq("paid")
      expect(committed).to eq([:paid])
    end
  end

  describe "11. CAS side effects" do
    it "touches updated_at (opt-out), syncs without dirty, writes changed_at, errors on a missing column" do
      define_standard_order(changed_at: true)
      order = Order.create!(updated_at: 2.days.ago)
      stale_updated_at = order.updated_at
      order.transition_to!(:cancelled)
      expect(order.changed?).to be(false)
      expect(order.reload.updated_at).to be > stale_updated_at
      expect(order.state_changed_at).not_to be_nil

      define_standard_order(touch: false)
      untouched = Order.create!(updated_at: 2.days.ago)
      frozen_updated_at = untouched.reload.updated_at
      untouched.transition_to!(:cancelled)
      expect(untouched.reload.updated_at).to be_within(1.second).of(frozen_updated_at)

      define_standard_order(changed_at: :missing_column)
      expect { Order.create!.transition_to!(:cancelled) }
        .to raise_error(Statecraft::CompilationError, /missing_column/)
    end
  end

  describe "12. FK cascade" do
    it "destroy and callback-free delete both drop log rows at the database level" do
      define_standard_order
      destroyed = Order.create!
      deleted = Order.create!
      destroyed.transition_to!(:cancelled)
      deleted.transition_to!(:cancelled)

      destroyed.destroy
      Order.where(id: deleted.id).delete_all

      expect(OrderTransition.where(order_id: destroyed.id)).to be_empty
      expect(OrderTransition.where(order_id: deleted.id)).to be_empty
    end
  end

  describe "13. generated CHECK boundaries" do
    it "fresh table gets the constraint, existing table gets the NOT VALID recipe instead" do
      require "rails/generators"
      require "generators/statecraft/machine/machine_generator"
      Dir.mktmpdir do |tmp|
        Statecraft::Generators::MachineGenerator.start(["Order", "--quiet"], destination_root: tmp)
        fresh = File.read(Dir[File.join(tmp, "db/migrate/*")].first)
        expect(fresh).to include("add_check_constraint")
      end
      Dir.mktmpdir do |tmp|
        FileUtils.mkdir_p(File.join(tmp, "app/models"))
        File.write(File.join(tmp, "app/models/order.rb"), "class Order < ApplicationRecord\nend\n")
        Statecraft::Generators::MachineGenerator.start(["Order", "--quiet"], destination_root: tmp)
        existing = File.read(Dir[File.join(tmp, "db/migrate/*")].first)
        expect(existing).not_to include("add_check_constraint")
        expect(existing).to include("NOT VALID")
      end
    end
  end

  describe "14-15. introspection surface" do
    it "reports via with :direct rules; may_ answers depend on metadata and match can_fire?" do
      define_standard_order(helpers: true)
      order = Order.create!
      by_target = order.available_transitions(metadata: { amount: 5 }).to_h { |a| [a.to, a.via] }
      expect(by_target[:paid]).to eq([:pay])
      expect(by_target[:cancelled]).to eq([:direct])
      expect(order.available_transitions(metadata: {}).map(&:to)).to eq([:cancelled])

      expect(order.may_pay?(metadata: { amount: 5 })).to be(true)
      expect(order.may_pay?).to be(false)
      expect(order.may_pay?(metadata: { amount: 5 })).to eq(order.can_fire?(:pay, metadata: { amount: 5 }))
    end
  end

  describe "16. transitioned_to? dictionary" do
    it "is false for initial without a return and true after a loop" do
      define_standard_order
      order = Order.create!
      expect(order.transitioned_to?(:pending)).to be(false)
      expect(order.in_state?(:pending)).to be(true)

      looped = Order.create!(state: "paid")
      looped.transition_to!(:paid)
      expect(looped.transitioned_to?(:paid)).to be(true)
    end
  end

  describe "17. scopes flag" do
    it "generates flat scopes only under scopes: true" do
      define_standard_order(scopes: true)
      expect(Order).to respond_to(:pending)
      define_standard_order
      expect(Order).not_to respond_to(:pending)
    end
  end

  describe "18. programmer errors" do
    it "raises DirtyRecordError on locked dirty and UnsavedRecordError on new records, both variants" do
      stub_const("LockFlow", Class.new do
        include Statecraft::Machine

        state :pending, initial: true
        state :cancelled
        transition from: :pending, to: :cancelled, lock: true
      end)
      stub_const("Order", Class.new(ActiveRecord::Base) { self.table_name = "orders" })
      stub_const("OrderTransition", Class.new(ActiveRecord::Base) { self.table_name = "order_transitions" })
      Order.state_machine(LockFlow)

      dirty = Order.create!
      dirty.status = "tampered"
      expect { dirty.transition_to!(:cancelled) }.to raise_error(Statecraft::DirtyRecordError)
      expect { Order.new.transition_to(:cancelled) }.to raise_error(Statecraft::UnsavedRecordError)
    end
  end

  describe "19. metadata contract" do
    it "round-trips before guards, freezes everywhere, rejects unserializable input instantly" do
      seen = nil
      stub_const("MetaFlow", Class.new do
        include Statecraft::Machine

        state :pending, initial: true
        state :paid
        event :pay, from: :pending, to: :paid, guard: lambda { |_r, metadata|
          seen = metadata
          true
        }
      end)
      stub_const("Order", Class.new(ActiveRecord::Base) { self.table_name = "orders" })
      stub_const("OrderTransition", Class.new(ActiveRecord::Base) { self.table_name = "order_transitions" })
      Order.state_machine(MetaFlow)

      row = Order.create!.fire!(:pay, metadata: { reason: :fraud })
      expect(seen).to eq({ "reason" => "fraud" })
      expect(seen).to be_frozen
      expect(row.metadata).to eq(seen)

      expect { Order.create!.can_fire?(:pay, metadata: { p: proc {} }) }
        .to raise_error(ArgumentError, /not JSON-serializable/)
    end
  end

  describe "20. STI" do
    it "inherits the machine, scopes narrow by type, guards see the subclass, remount raises" do
      guard_classes = []
      stub_const("StiFlow", Class.new do
        include Statecraft::Machine

        state :pending, initial: true
        state :paid
        event :pay, from: :pending, to: :paid, guard: lambda { |record, _m|
          guard_classes << record.class.name
          true
        }
      end)
      stub_const("Order", Class.new(ActiveRecord::Base) { self.table_name = "orders" })
      stub_const("OrderTransition", Class.new(ActiveRecord::Base) { self.table_name = "order_transitions" })
      Order.state_machine(StiFlow, scopes: true, helpers: true)
      stub_const("CreditOrder", Class.new(Order))

      credit = CreditOrder.create!
      credit.pay!
      expect(credit.reload.state).to eq("paid")
      expect(guard_classes).to eq(["CreditOrder"])
      expect(CreditOrder.paid.to_sql).to include(%("orders"."type"))
      expect(OrderTransition.where(order_id: credit.id).count).to eq(1)
      expect { CreditOrder.state_machine(StiFlow) }.to raise_error(Statecraft::AlreadyMounted)
    end
  end

  describe "21. multi-database boundary" do
    it "raises ConnectionMismatch for a log on a foreign connection class" do
      stub_const("MonoFlow", Class.new do
        include Statecraft::Machine

        state :pending, initial: true
      end)
      stub_const("Order", Class.new(ActiveRecord::Base) { self.table_name = "orders" })
      foreign_base = Class.new(ActiveRecord::Base) { self.abstract_class = true }
      stub_const("ForeignBase", foreign_base)
      ForeignBase.establish_connection(adapter: "sqlite3", database: ":memory:")
      stub_const("ForeignLog", Class.new(ForeignBase) { self.table_name = "order_transitions" })

      expect { Order.state_machine(MonoFlow, log: ForeignLog) }
        .to raise_error(Statecraft::ConnectionMismatch)
    end
  end

  describe "22. the transactional invariant and telemetry" do
    it "after_commit behaves like a model after_commit in the same transaction, and telemetry names follow outcomes" do
      statecraft_commits = []
      model_commits = []
      stub_const("InvFlow", Class.new do
        include Statecraft::Machine

        state :pending, initial: true
        state :paid
        event :pay, from: :pending, to: :paid
        after_commit ->(_r, _t) { statecraft_commits << :ran }
      end)
      stub_const("Order", Class.new(ActiveRecord::Base) do
        self.table_name = "orders"
        after_commit -> { model_commits << :ran }, on: :update
      end)
      stub_const("OrderTransition", Class.new(ActiveRecord::Base) { self.table_name = "order_transitions" })
      Order.state_machine(InvFlow)

      order = Order.create!
      control = Order.create!
      Order.transaction do
        order.fire!(:pay)
        control.update!(status: "bump")
        expect(statecraft_commits.empty?).to eq(model_commits.empty?)
      end
      expect(statecraft_commits.empty?).to eq(model_commits.empty?)
      expect(statecraft_commits).to eq([:ran])

      events = []
      subscription = ActiveSupport::Notifications.subscribe(/statecraft\z/) do |name, _s, _f, _id, payload|
        events << [name, payload[:reason]]
      end
      begin
        fresh = Order.create!
        fresh.fire!(:pay)
        fresh.fire(:pay)
      ensure
        ActiveSupport::Notifications.unsubscribe(subscription)
      end
      expect(events).to include(["transition.statecraft", nil])
      expect(events).to include(["transition_failed.statecraft", :invalid_transition])
    end
  end

  describe "hygiene" do
    it "keeps the runtime free of Rails in an isolated process" do
      probe = 'require "statecraft"; abort("Rails leaked") unless defined?(Rails).nil?'
      output = IO.popen([RbConfig.ruby, "-Ilib", "-e", probe], err: %i[child out], &:read)
      expect($CHILD_STATUS).to be_success, output
    end
  end
end
