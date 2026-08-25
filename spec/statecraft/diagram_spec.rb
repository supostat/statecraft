# frozen_string_literal: true

RSpec.describe "mermaid export" do
  def machine_class(&definition)
    Class.new do
      include Statecraft::Machine

      class_eval(&definition)
    end
  end

  it "renders the showcase graph: initial marker, event label and a bare direct edge" do
    flow = machine_class do
      state :pending, initial: true
      state :paid
      state :cancelled

      event :pay, from: :pending, to: :paid
      transition from: :pending, to: :cancelled
    end

    expect(flow.to_mermaid).to eq(<<~MERMAID)
      stateDiagram-v2
        [*] --> pending
        pending --> paid : pay
        pending --> cancelled
    MERMAID
  end

  it "renders several events on one edge as a single labeled arrow" do
    flow = machine_class do
      state :pending, initial: true
      state :cancelled

      event :cancel, from: :pending, to: :cancelled
      event :admin_override, from: :pending, to: :cancelled
    end

    expect(flow.to_mermaid).to eq(<<~MERMAID)
      stateDiagram-v2
        [*] --> pending
        pending --> cancelled : cancel / admin_override
    MERMAID
  end

  it "renders a loop edge" do
    flow = machine_class do
      state :paid, initial: true

      event :pay_again, from: :paid, to: :paid
    end

    expect(flow.to_mermaid).to eq(<<~MERMAID)
      stateDiagram-v2
        [*] --> paid
        paid --> paid : pay_again
    MERMAID
  end

  it "returns an identical string on a repeated call" do
    flow = machine_class do
      state :a, initial: true
      state :b

      event :go, from: :a, to: :b
    end

    expect(flow.to_mermaid).to eq(flow.to_mermaid)
  end

  it "never renders guard names of either nature" do
    flow = machine_class do
      state :pending, initial: true
      state :cancelled

      event :cancel, from: :pending, to: :cancelled,
                     record_guard: :customer_cancellable?, guard: :reason_present?

      private

      def customer_cancellable?(record) = record.customer_cancellable?

      def reason_present?(_record, metadata)
        metadata["reason"].to_s.strip != ""
      end
    end

    rendered = flow.to_mermaid

    expect(rendered).to include("cancel")
    expect(rendered).not_to include("customer_cancellable?")
    expect(rendered).not_to include("reason_present?")
  end
end
