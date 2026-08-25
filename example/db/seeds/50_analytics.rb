# frozen_string_literal: true

module AnalyticsSeeds
  module_function

  # Both databases are writable from one seed run; the archived event walks
  # the honest pipeline, so the second database's log carries a row from
  # birth of the corpus.
  def seed_events
    Analytics::Event.create!(name: "page_view")
    archived = Analytics::Event.create!(name: "session_start")
    archived.archive!(metadata: { "note" => "seeded archive" })
    archived
  end
end

return if Analytics::Event.any?

AnalyticsSeeds.seed_events
