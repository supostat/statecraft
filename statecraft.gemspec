# frozen_string_literal: true

require_relative "lib/statecraft/version"

Gem::Specification.new do |spec|
  spec.name = "statecraft"
  spec.version = Statecraft::VERSION
  spec.authors = ["Igor Pugachev"]
  spec.email = ["ipugachev84@gmail.com"]

  spec.summary = "Concurrency-safe state machine for ActiveRecord with an append-only transition log"
  spec.description = "State machine on top of ActiveRecord: the current state lives in a column " \
                     "guarded by CAS updates, history is an append-only per-model log with " \
                     "write-once metadata, guards are event-aware, and bypass is explicit."
  spec.license = "MIT"
  spec.homepage = "https://supostat.github.io/statecraft/"

  spec.required_ruby_version = ">= 3.3"

  # .tt and USAGE too: the generator templates and help text are part of the
  # shipped gem, and a *.rb-only mask silently published a generator without them.
  spec.files = Dir["lib/**/*.{rb,tt}", "lib/**/USAGE", "LICENSE.txt", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "activerecord", ">= 7.2", "< 9"
  spec.add_dependency "activesupport", ">= 7.2", "< 9"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/supostat/statecraft"
  spec.metadata["changelog_uri"] = "https://github.com/supostat/statecraft/releases"
  spec.metadata["bug_tracker_uri"] = "https://github.com/supostat/statecraft/issues"
  spec.metadata["rubygems_mfa_required"] = "true"
end
