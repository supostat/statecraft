# frozen_string_literal: true

module Statecraft
  # Executes one transition through the protocol pipeline:
  #
  #   persisted? -> metadata normalize+freeze -> edge resolution ->
  #   dirty check (lock only) -> transaction(requires_new: true) [
  #     lock+reload -> re-resolve edge from fresh state -> guards ->
  #     before_transition -> CAS UPDATE -> log INSERT (insert path) ->
  #     after_transition
  #   ] -> after_commit registration on the outermost real commit
  #
  # The CAS statement and the log insert run against base_class; the log row
  # is written via the insert path, past the log model's validations and
  # callbacks — guards and machine callbacks are the single channel of truth.
  class Pipeline
    Transition = Struct.new(:from, :to, :event, :metadata, :log_record, keyword_init: true)

    # One frame per pipeline currently running in this execution context. The
    # key identifies the record across instances — (base_class name, id,
    # machine) — so re-entering the same record's pipeline between its start
    # and the completion of CAS (guards, before_transition) is caught even
    # through a freshly loaded instance. cas_done flips right after the CAS
    # statement: chains launched from after_transition are legal by
    # construction.
    Frame = Struct.new(:key, :label, :cas_done, keyword_init: true)

    STACK_KEY = :statecraft_transition_stack
    MAX_CHAIN_DEPTH = 16

    def self.transition_stack
      ActiveSupport::IsolatedExecutionState[STACK_KEY] ||= []
    end

    # The record-facing API mixed into the model at mounting time. Bang
    # variants return the created log record; non-bang variants return it too,
    # or false on GuardFailed / InvalidTransition. Programmer errors and
    # TransitionConflict always raise.
    module Surface
      def transition_to!(to_state, metadata: {}, bypass_events: false)
        Pipeline.new(self).direct(to_state, metadata: metadata, bypass_events: bypass_events)
      end

      def transition_to(to_state, metadata: {}, bypass_events: false)
        transition_to!(to_state, metadata: metadata, bypass_events: bypass_events)
      rescue GuardFailed, InvalidTransition
        false
      end

      def fire!(event_name, metadata: {})
        Pipeline.new(self).fire(event_name, metadata: metadata)
      end

      def fire(event_name, metadata: {})
        fire!(event_name, metadata: metadata)
      rescue GuardFailed, InvalidTransition
        false
      end
    end

    def initialize(record)
      @record = record
      @configuration = record.class.statecraft_mounting
      @graph = @configuration.machine_class.finalize!
      @machine_instance = @configuration.machine_class.new
    end

    def direct(to_state, metadata:, bypass_events:)
      run(metadata) do |current_state|
        edge = resolve_direct_edge(current_state, to_state.to_sym, bypass_events)
        [edge, nil, bypass_events]
      end
    end

    def fire(event_name, metadata:)
      run(metadata) do |current_state|
        edge = resolve_event_edge(current_state, event_name.to_sym)
        [edge, event_name.to_sym, false]
      end
    end

    private

    attr_reader :record, :configuration, :graph, :machine_instance

    def run(raw_metadata, &edge_resolver)
      raise UnsavedRecordError.new(record: record) unless record.persisted?

      metadata = Metadata.normalize(raw_metadata)
      started_at = Time.current
      begin
        edge, event, bypass = edge_resolver.call(current_state)
        assert_clean_when_locked(edge)
        frame = open_frame(edge, event)
        begin
          log_record = execute_transaction(edge, event, bypass, metadata, edge_resolver, frame)
        ensure
          Pipeline.transition_stack.delete(frame)
        end
      rescue GuardFailed => guard_error
        publish_failure(started_at, :guard_failed, guard: guard_error.guard)
        raise
      rescue InvalidTransition => invalid_error
        publish_failure(started_at, :invalid_transition, requested: invalid_error.requested)
        raise
      rescue TransitionConflict => conflict_error
        publish_failure(started_at, :conflict, expected_from: conflict_error.expected_from)
        raise
      end
      Instrumentation.publish_transition(
        started_at: started_at, record: record,
        machine_class: configuration.machine_class, log_record: log_record
      )
      register_after_commit_callbacks(log_record, metadata)
      log_record
    end

    def publish_failure(started_at, reason, details)
      Instrumentation.publish_failure(
        started_at: started_at, record: record,
        machine_class: configuration.machine_class, reason: reason, details: details
      )
    end

    def execute_transaction(edge, event, bypass, metadata, edge_resolver, frame)
      base_class.transaction(requires_new: true) do
        if edge.lock
          warn_when_row_locking_unavailable
          record.reload(lock: true)
          edge, event, bypass = edge_resolver.call(current_state)
        end
        transition_time = Time.current
        run_guards(edge, event, bypass, metadata)
        context = Transition.new(
          from: edge.from, to: edge.to, event: event, metadata: metadata, log_record: nil
        )
        run_callbacks(:before_transition, context)
        cas_update!(edge, transition_time)
        frame.cas_done = true
        context.log_record = insert_log_row(edge, event, metadata, transition_time)
        sync_record(edge, transition_time)
        run_callbacks(:after_transition, context)
        context.log_record
      end
    end

    def open_frame(edge, event)
      stack = Pipeline.transition_stack
      frame_key = [base_class.name, record.id, configuration.machine_class]
      pending_same_record = stack.find { |open| open.key == frame_key && !open.cas_done }
      raise NestedTransitionError.new(record: record) if pending_same_record

      if stack.length >= MAX_CHAIN_DEPTH
        chain = stack.map(&:label) + [frame_label(edge, event)]
        raise ChainDepthExceeded.new(chain: chain)
      end

      frame = Frame.new(key: frame_key, label: frame_label(edge, event), cas_done: false)
      stack.push(frame)
      frame
    end

    def frame_label(edge, event)
      via = event ? " (#{event})" : ""
      "#{base_class.name}##{record.id}: #{edge.from} -> #{edge.to}#{via}"
    end

    def current_state
      record[configuration.column].to_s.to_sym
    end

    def resolve_direct_edge(current, to_state, bypass_events)
      edge = graph.edges[[current, to_state]]
      raise_invalid_transition(current, to_state) if edge.nil?
      guarding_events = edge.event_names.select { |name| edge.event_guards[name].any? }
      if guarding_events.any? && !bypass_events
        raise InvalidTransition.new(
          record: record, from: current, requested: to_state,
          allowed: allowed_targets(current),
          message: "direct transition #{current} -> #{to_state} is guarded by " \
                   "event#{"s" if guarding_events.length > 1} #{guarding_events.join(", ")}; " \
                   "call fire!(:#{guarding_events.first}) or pass bypass_events: true"
        )
      end
      edge
    end

    def resolve_event_edge(current, event_name)
      branches = graph.events[event_name]
      raise_invalid_transition(current, event_name) if branches.nil?
      edge = branches[current]
      raise_invalid_transition(current, event_name) if edge.nil?
      edge
    end

    def raise_invalid_transition(current, requested)
      raise InvalidTransition.new(
        record: record, from: current, requested: requested,
        allowed: allowed_targets(current)
      )
    end

    def allowed_targets(current)
      graph.edges.keys.select { |from, _to| from == current }.map(&:last)
    end

    def assert_clean_when_locked(edge)
      return unless edge.lock && record.changed?

      raise DirtyRecordError.new(record: record, changed_attributes: record.changed)
    end

    def run_guards(edge, event, bypass, metadata)
      guards = edge.edge_guards.dup
      guards.concat(edge.event_guards.fetch(event, [])) if event && !bypass
      guards.each do |guard|
        next if Machine::Handlers.invoke(machine_instance, guard, record, metadata)

        raise GuardFailed.new(
          record: record, guard: guard.is_a?(Symbol) ? guard : guard.inspect,
          from: edge.from, to: edge.to, event: event
        )
      end
    end

    def run_callbacks(phase, context)
      matching_callbacks(phase, context).each do |callback|
        Machine::Handlers.invoke(machine_instance, callback.handler, record, context)
      end
    end

    def matching_callbacks(phase, context)
      graph.callbacks.fetch(phase).select do |callback|
        (callback.from.nil? || callback.from.include?(context.from)) &&
          (callback.to.nil? || callback.to.include?(context.to)) &&
          (callback.event.nil? || (context.event && callback.event.include?(context.event)))
      end
    end

    def cas_update!(edge, transition_time)
      affected_rows = base_class.unscoped
                                .where(base_class.primary_key => record.id,
                                       configuration.column => edge.from.to_s)
                                .update_all(cas_updates(edge, transition_time))
      raise TransitionConflict.new(record: record, expected_from: edge.from) if affected_rows.zero?
    end

    def cas_updates(edge, transition_time)
      updates = { configuration.column => edge.to.to_s }
      updates[:updated_at] = transition_time if touch_updated_at?
      updates[changed_at_column] = transition_time if changed_at_column
      updates
    end

    def insert_log_row(edge, event, metadata, transition_time)
      log_class = configuration.log_class
      attributes = {
        configuration.log_foreign_key => record.id,
        from_state: edge.from.to_s,
        to_state: edge.to.to_s,
        event: event&.to_s,
        metadata: metadata,
        created_at: transition_time
      }
      result = log_class.insert!(attributes, returning: [log_class.primary_key.to_sym])
      log_id = result.rows.first&.first
      log_class.find(log_id)
    end

    def sync_record(edge, transition_time)
      synced_columns = [configuration.column]
      record[configuration.column] = edge.to.to_s
      if touch_updated_at?
        record[:updated_at] = transition_time
        synced_columns << :updated_at
      end
      if changed_at_column
        record[changed_at_column] = transition_time
        synced_columns << changed_at_column
      end
      record.clear_attribute_changes(synced_columns)
    end

    def register_after_commit_callbacks(log_record, metadata)
      context = Transition.new(
        from: log_record.from_state.to_sym, to: log_record.to_state.to_sym,
        event: log_record.event&.to_sym, metadata: metadata, log_record: log_record
      )
      matching_callbacks(:after_commit, context).each do |callback|
        ActiveRecord.after_all_transactions_commit do
          Machine::Handlers.invoke(machine_instance, callback.handler, record, context)
        end
      end
    end

    def touch_updated_at?
      configuration.touch && record.class.column_names.include?("updated_at")
    end

    def changed_at_column
      column = configuration.changed_at_column
      return nil unless column

      unless record.class.column_names.include?(column.to_s)
        raise CompilationError,
              "changed_at column #{column} does not exist on #{record.class.table_name}; " \
              "add the column or drop the changed_at option"
      end
      column
    end

    def warn_when_row_locking_unavailable
      return unless base_class.connection.adapter_name.match?(/sqlite/i)

      Statecraft.warn(
        [configuration.machine_class.name, :sqlite_row_lock],
        "row locking unavailable on sqlite (machine #{configuration.machine_class.name}); " \
        "the reload still runs, but lock: true guarantees require PostgreSQL"
      )
    end

    def base_class
      record.class.base_class
    end
  end
end
