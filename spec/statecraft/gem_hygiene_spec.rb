# frozen_string_literal: true

require "English"

RSpec.describe "gem hygiene" do
  it "neither defines Rails nor loads railties after require statecraft (isolated process)" do
    probe = <<~RUBY
      require "statecraft"
      failures = []
      failures << "Rails is defined" unless defined?(Rails).nil?
      railties = $LOADED_FEATURES.grep(%r{/railties[/-]})
      failures << "railties loaded: \#{railties.first}" unless railties.empty?
      abort(failures.join("; ")) unless failures.empty?
    RUBY

    output = IO.popen([RbConfig.ruby, "-Ilib", "-e", probe], err: %i[child out], &:read)
    expect($CHILD_STATUS).to be_success, "gem loads Rails at runtime: #{output}"
  end

  it "keeps statecraft/rspec out of the core require (isolated process)" do
    probe = <<~RUBY
      require "statecraft"
      loaded = $LOADED_FEATURES.grep(%r{statecraft/rspec})
      abort("statecraft/rspec loaded eagerly: \#{loaded.first}") unless loaded.empty?
    RUBY

    output = IO.popen([RbConfig.ruby, "-Ilib", "-e", probe], err: %i[child out], &:read)
    expect($CHILD_STATUS).to be_success, "the core require pulls the matchers in: #{output}"
  end

  it "refuses statecraft/rspec without RSpec, naming the fix (isolated process)" do
    probe = <<~RUBY
      begin
        require "statecraft/rspec"
        abort("statecraft/rspec loaded without RSpec present")
      rescue Statecraft::Error => error
        abort("unhelpful message: \#{error.message}") unless error.message.include?("RSpec")
      end
    RUBY

    output = IO.popen([RbConfig.ruby, "-Ilib", "-e", probe], err: %i[child out], &:read)
    expect($CHILD_STATUS).to be_success, output
  end

  it "exposes a semantic version" do
    expect(Statecraft::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
  end

  it "roots every error in Statecraft::Error" do
    error_classes = [
      Statecraft::GuardFailed,
      Statecraft::InvalidTransition,
      Statecraft::TransitionConflict,
      Statecraft::StaleTransition,
      Statecraft::UnsavedRecordError,
      Statecraft::DirtyRecordError,
      Statecraft::NestedTransitionError,
      Statecraft::ChainDepthExceeded,
      Statecraft::AlreadyMounted,
      Statecraft::CompositePrimaryKeyUnsupported,
      Statecraft::ConnectionMismatch,
      Statecraft::MetadataRequired
    ]

    error_classes.each do |error_class|
      expect(error_class.ancestors).to include(Statecraft::Error)
    end
  end

  it "keeps Statecraft::Error a StandardError" do
    expect(Statecraft::Error.superclass).to eq(StandardError)
  end
end
