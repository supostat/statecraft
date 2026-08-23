# frozen_string_literal: true

require "statecraft"

module SpecDatabase
  def self.connect!
    if ENV["DATABASE_URL"]
      ActiveRecord::Base.establish_connection(ENV["DATABASE_URL"])
    else
      ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
    end
  end

  def self.postgres?
    ActiveRecord::Base.connection_db_config.adapter.start_with?("postgres")
  end

  def self.define_schema(&table_definitions)
    ActiveRecord::Schema.verbose = false
    ActiveRecord::Schema.define(&table_definitions)
  end
end

SpecDatabase.connect!

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
end
