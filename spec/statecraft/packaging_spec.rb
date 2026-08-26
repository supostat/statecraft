# frozen_string_literal: true

require "rubygems"

RSpec.describe "gem packaging" do
  let(:specification) do
    Gem::Specification.load(File.expand_path("../../statecraft.gemspec", __dir__))
  end

  it "ships every generator template" do
    templates = Dir["lib/generators/**/templates/*.tt"]

    expect(templates).not_to be_empty
    expect(specification.files).to include(*templates)
  end

  it "ships every library file" do
    expect(specification.files).to include(*Dir["lib/**/*.rb"])
  end

  it "ships every generator USAGE" do
    expect(specification.files).to include("lib/generators/statecraft/machine/USAGE",
                                           "lib/generators/statecraft/from_statesman/USAGE")
  end

  it "ships the license and the readme" do
    expect(specification.files).to include("LICENSE.txt", "README.md")
  end

  # The example app pins the gem by path and CI installs it with a frozen
  # lockfile, so a version bump that forgets `bundle lock` in example/ turns
  # CI red long after the fact — this catches it in the same suite run.
  it "keeps the example lockfile on the current gem version" do
    lockfile = File.read(File.expand_path("../../example/Gemfile.lock", __dir__))

    expect(lockfile).to include("statecraft (#{Statecraft::VERSION})")
  end

  it "points at the project's public addresses" do
    expect(specification.homepage).to eq("https://supostat.github.io/statecraft/")
    expect(specification.metadata).to include(
      "source_code_uri" => "https://github.com/supostat/statecraft",
      "changelog_uri" => "https://github.com/supostat/statecraft/releases",
      "bug_tracker_uri" => "https://github.com/supostat/statecraft/issues"
    )
  end
end
