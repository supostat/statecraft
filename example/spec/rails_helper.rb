# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"

require_relative "../config/environment"

abort("The Rails environment is running in #{Rails.env} mode!") unless Rails.env.test?

require "rspec/rails"
require "capybara/rspec"
require_relative "spec_helper"

ActiveRecord::Migration.maintain_test_schema!

RSpec.configure do |config|
  # db:seed is the e2e fixture set: seeded ONCE per suite run into freshly
  # truncated databases, then every example rolls back around it. Specs find
  # records by attributes, never by id; seed helpers return the records they
  # made. The N-thread race spec is the one named non-transactional
  # exception and cleans up after itself.
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!

  config.before(:suite) do
    [ApplicationRecord, AnalyticsRecord].each do |base|
      connection = base.connection
      (connection.tables - %w[schema_migrations ar_internal_metadata]).each do |table|
        connection.execute("TRUNCATE TABLE #{connection.quote_table_name(table)} RESTART IDENTITY CASCADE")
      end
    end
    Rails.application.load_seed
  end

  config.before(:each, type: :system) do
    driven_by :rack_test
  end
end
