# frozen_string_literal: true

module Statecraft
  # The single internal warning funnel. Speaks to the developer at the
  # keyboard through Kernel#warn (stderr) — never through Rails.logger, which
  # may not exist, may be unconfigured at mounting time, and hides test-run
  # warnings in a log file nobody reads. Deduplicates once-per-key-per-process
  # and is deliberately not configurable: a "where do warnings go" knob would
  # be the first global setting of a gem that has none.
  def self.warn(key, message)
    WARNING_DEDUP_MUTEX.synchronize do
      return if emitted_warning_keys.include?(key)

      emitted_warning_keys << key
    end
    Kernel.warn("[statecraft] #{message}")
  end

  WARNING_DEDUP_MUTEX = Mutex.new

  def self.emitted_warning_keys
    @emitted_warning_keys ||= Set.new
  end
  private_class_method :emitted_warning_keys

  def self.reset_warning_dedup!
    WARNING_DEDUP_MUTEX.synchronize { emitted_warning_keys.clear }
  end
  private_class_method :reset_warning_dedup!
end
