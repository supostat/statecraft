# frozen_string_literal: true

RSpec.describe "gem hygiene" do
  it "does not define Rails after require statecraft" do
    expect(defined?(Rails)).to be_nil
  end

  it "does not load railties" do
    expect($LOADED_FEATURES.grep(%r{/railties[/-]})).to be_empty
  end

  it "exposes a semantic version" do
    expect(Statecraft::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
  end

  it "roots every error in Statecraft::Error" do
    error_classes = [
      Statecraft::GuardFailed,
      Statecraft::InvalidTransition,
      Statecraft::TransitionConflict,
      Statecraft::UnsavedRecordError,
      Statecraft::DirtyRecordError,
      Statecraft::NestedTransitionError,
      Statecraft::ChainDepthExceeded,
      Statecraft::AlreadyMounted,
      Statecraft::CompositePrimaryKeyUnsupported,
      Statecraft::ConnectionMismatch
    ]

    error_classes.each do |error_class|
      expect(error_class.ancestors).to include(Statecraft::Error)
    end
  end

  it "keeps Statecraft::Error a StandardError" do
    expect(Statecraft::Error.superclass).to eq(StandardError)
  end
end
