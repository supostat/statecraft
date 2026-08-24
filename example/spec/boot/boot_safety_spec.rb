# frozen_string_literal: true

require "rails_helper"

# catalog: 36-boot-safety
# catalog: 37-telemetry-subscriber

RSpec.describe "boot safety" do
  it "eager loads the whole app under Zeitwerk" do
    expect { Rails.application.eager_load! }.not_to raise_error
  end

  it "writes the primary database" do
    entry = OperationEntry.create!(
      record_class: "BootProbe", record_id: "0", outcome: "transition"
    )
    expect(entry).to be_persisted
  end

  it "writes the analytics database" do
    connection = AnalyticsRecord.connection
    connection.execute("CREATE TEMPORARY TABLE boot_probe (value integer)")
    connection.execute("INSERT INTO boot_probe (value) VALUES (1)")
    expect(connection.select_value("SELECT count(*) FROM boot_probe")).to eq(1)
  end

  it "feeds the operations log from the gem's telemetry bus" do
    payload = {
      record_class: "BootProbe", record_id: 1,
      machine: "BootProbeFlow", from: :pending, to: :paid, event: :pay
    }
    expect do
      ActiveSupport::Notifications.publish(
        "transition.statecraft", Time.current, Time.current, "statecraft", payload
      )
    end.to change(OperationEntry, :count).by(1)

    entry = OperationEntry.feed.last
    expect(entry.event_name).to eq("pay")
    expect(entry.outcome).to eq("transition")
  end

  it "records refusals with their reason" do
    payload = {
      record_class: "BootProbe", record_id: 1,
      machine: "BootProbeFlow", from: :pending, to: :paid, event: :pay,
      reason: "guard_failed"
    }
    expect do
      ActiveSupport::Notifications.publish(
        "transition_failed.statecraft", Time.current, Time.current, "statecraft", payload
      )
    end.to change(OperationEntry.where(outcome: "refused"), :count).by(1)
  end
end
