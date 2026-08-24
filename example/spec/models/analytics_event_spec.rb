# frozen_string_literal: true

require "rails_helper"

# catalog: 34-second-database-hermetic

RSpec.describe Analytics::Event do
  it "lives hermetically in the second database, log included" do
    expect(described_class.connection_db_config.name).to eq("analytics")
    expect(Analytics::EventTransition.connection_db_config.name).to eq("analytics")
    expect(described_class.connection_db_config.database)
      .not_to eq(ApplicationRecord.connection_db_config.database)
  end

  it "records in the initial state and archives through the honest pipeline" do
    event = described_class.create!(name: "spec_probe")
    expect(event[:state]).to eq("recorded")
    expect(event.history).to be_empty

    log_row = event.archive!(metadata: { "note" => "spec" })

    expect(event[:state]).to eq("archived")
    expect(log_row).to be_a(Analytics::EventTransition)
    expect(log_row.event).to eq("archive")
    expect(event.history.count).to eq(1)
  end

  it "keeps the seeded corpus alive: one recorded, one archived with a log row from birth" do
    expect(described_class.recorded.pluck(:name)).to include("page_view")
    archived = described_class.archived.find_by!(name: "session_start")
    expect(archived.last_transition.event).to eq("archive")
  end
end
