# frozen_string_literal: true

module Statecraft
  class Error < StandardError; end

  class CompilationError < Error; end

  class GuardFailed < Error
    attr_reader :record, :guard, :from, :to, :event

    def initialize(record:, guard:, from:, to:, event:)
      @record = record
      @guard = guard
      @from = from
      @to = to
      @event = event
      via = event ? " (event #{event})" : nil
      super("guard #{guard.inspect} failed for #{record.class.name}##{record.id} " \
            "on #{from} -> #{to}#{via}")
    end
  end

  class InvalidTransition < Error
    attr_reader :record, :from, :requested, :allowed

    def initialize(record:, from:, requested:, allowed:, message: nil)
      @record = record
      @from = from
      @requested = requested
      @allowed = allowed
      default_message = "transition #{from} -> #{requested} is not declared for " \
                        "#{record.class.name}; allowed from #{from}: " \
                        "#{allowed.empty? ? "none" : allowed.join(", ")}"
      super(message || default_message)
    end
  end

  class TransitionConflict < Error
    attr_reader :record, :expected_from

    def initialize(record:, expected_from:, message: nil)
      @record = record
      @expected_from = expected_from
      super(message || "concurrent update detected for #{record.class.name}##{record.id}: " \
                       "expected state #{expected_from.inspect}, another writer got there first")
    end
  end

  # The refusal of a seen: token: the snapshot the caller acted on is not
  # the row's version — or could not be read at all, which is the same
  # answer with nothing to compare (expected_version stays nil). A subclass
  # of TransitionConflict, so existing rescues keep catching it;
  # controllers map it to 409 specifically.
  class StaleTransition < TransitionConflict
    attr_reader :expected_version, :seen

    def initialize(record:, expected_from:, expected_version:, seen:)
      @expected_version = expected_version
      @seen = seen
      reason =
        if expected_version.nil?
          "the token #{seen.inspect} is not a readable version"
        else
          "the caller saw version #{seen.inspect}, but the row has moved on"
        end
      super(record: record, expected_from: expected_from,
            message: "stale transition for #{record.class.name}##{record.id}: #{reason}")
    end
  end

  class UnsavedRecordError < Error
    attr_reader :record

    def initialize(record:)
      @record = record
      super("cannot transition an unsaved #{record.class.name}: save the record first; " \
            "initial state comes from the column default")
    end
  end

  class DirtyRecordError < Error
    attr_reader :record, :changed_attributes

    def initialize(record:, changed_attributes:)
      @record = record
      @changed_attributes = changed_attributes
      super("cannot lock-transition #{record.class.name}##{record.id} with unsaved changes " \
            "(#{changed_attributes.join(", ")}): save or reload before transitioning")
    end
  end

  class NestedTransitionError < Error
    attr_reader :record

    def initialize(record:)
      @record = record
      super("transition initiated from before_transition or a guard of another transition " \
            "on #{record.class.name}##{record.id}; move it to after_transition or outside")
    end
  end

  class ChainDepthExceeded < Error
    attr_reader :chain

    def initialize(chain:)
      @chain = chain
      super("transition chain exceeded depth #{chain.length}: #{chain.join(" -> ")}")
    end
  end

  class AlreadyMounted < Error
    attr_reader :model

    def initialize(model:)
      @model = model
      super("#{model.name} already carries a state machine; inheritance shares the base " \
            "machine, and per-subclass machines are out of v0")
    end
  end

  class CompositePrimaryKeyUnsupported < Error
    attr_reader :model

    def initialize(model:)
      @model = model
      super("#{model.name} uses a composite primary key; statecraft v0 supports " \
            "single-column primary keys only")
    end
  end

  class ConnectionMismatch < Error
    attr_reader :model, :log_class

    def initialize(model:, log_class:)
      @model = model
      @log_class = log_class
      super("#{log_class.name} does not share #{model.name}'s connection " \
            "(#{log_class.connection_specification_name} vs #{model.connection_specification_name}); " \
            "make the log model inherit from the model's connection-owning ancestor")
    end
  end
end
