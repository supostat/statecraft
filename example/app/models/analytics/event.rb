# frozen_string_literal: true

module Analytics
  # The hermetic tenant of the second database: its machine, its log and its
  # rows all live in analytics, and nothing here touches the primary
  # connection — deliberately unlinked from the order flow (a cross-database
  # coupling would widen the contagion radius and prove nothing visible).
  class Event < AnalyticsRecord
    state_machine EventFlow, helpers: true, scopes: true
  end
end
