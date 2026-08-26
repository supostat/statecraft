# frozen_string_literal: true

module Statecraft
  class Pipeline
    # The tagged half of the CAS: when the mounting carries versioning, every
    # transition compares-and-swaps on (state, version) and increments the
    # version in the same UPDATE. A seen: token substitutes the compared
    # value with what the caller's form actually rendered, and its refusal is
    # StaleTransition — the 409 of the pipeline.
    module Versioning
      private

      def version_column
        column = configuration.version_column
        return nil unless column

        unless record.class.column_names.include?(column.to_s)
          raise CompilationError,
                "versioning column #{column} does not exist on #{record.class.table_name}; " \
                "add the column or drop the versioning option"
        end
        column
      end

      def normalize_seen(raw_seen)
        return nil if raw_seen.nil?

        unless configuration.version_column
          raise CompilationError,
                "seen: requires versioning: true on the mounting of #{record.class.name}; " \
                "add the option or drop the token"
        end
        Integer(raw_seen)
      end

      # What the CAS requires the row's version to be: the caller's seen:
      # token when given, the in-memory value otherwise — fresh after a lock
      # reload, synced by the previous link inside a chain.
      def expected_version
        @seen || record[version_column]
      end

      # With a seen: token any versioned refusal is staleness — the caller
      # acted on a snapshot; without one it is the ordinary conflict of two
      # writers.
      def cas_refusal(edge)
        if @seen
          StaleTransition.new(record: record, expected_from: edge.from,
                              expected_version: expected_version, seen: @raw_seen)
        else
          TransitionConflict.new(record: record, expected_from: edge.from)
        end
      end

      # The same early observation as assert_lock_saw_expected_state, for the
      # seen: token: the reload holds the row's real version under the lock,
      # so a mismatched token is a stale snapshot detected deterministically,
      # before any write.
      def assert_lock_saw_expected_version(edge)
        return unless @seen && version_column
        return if record[version_column] == @seen

        raise StaleTransition.new(record: record, expected_from: edge.from,
                                  expected_version: @seen, seen: @raw_seen)
      end
    end
  end
end
