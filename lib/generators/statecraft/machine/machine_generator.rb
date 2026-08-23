# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

module Statecraft
  module Generators
    # `rails generate statecraft:machine Order` — the single statecraft
    # generator. Creates the migration (state column, optional changed_at,
    # the per-model log table with a cascade FK and a CHECK constraint for a
    # freshly created table), the machine class, the readonly log model, the
    # model mounting with helpers and scopes on, and lazily the shared
    # ApplicationMachine parent. The migration lands in the migration path of
    # the model's connection owner, so multi-database apps get it next to
    # their model.
    class MachineGenerator < Rails::Generators::NamedBase
      include ActiveRecord::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      def detect_model_presence
        @existing_model = File.exist?(File.join(destination_root, "app/models/#{file_name}.rb"))
      end

      def create_application_machine
        application_machine_path = "app/state_machines/application_machine.rb"
        return if File.exist?(File.join(destination_root, application_machine_path))

        template "application_machine.rb.tt", application_machine_path
      end

      def create_machine_class
        template "machine.rb.tt", "app/state_machines/#{file_name}_flow.rb"
      end

      def create_log_model
        template "log_model.rb.tt", "app/models/#{file_name}_transition.rb"
      end

      def create_or_mount_model
        if existing_model?
          inject_into_class "app/models/#{file_name}.rb", class_name, mounting_line
        else
          template "model.rb.tt", "app/models/#{file_name}.rb"
        end
      end

      def create_migration_file
        migration_source = existing_model? ? "add_migration.rb.tt" : "create_migration.rb.tt"
        migration_template migration_source,
                           "#{migration_directory}/create_#{file_name}_state_machine.rb"
      end

      private

      def existing_model?
        @existing_model
      end

      def mounting_line
        "  state_machine #{class_name}Flow, changed_at: true, helpers: true, scopes: true\n"
      end

      def migration_directory
        specification_name = model_connection_specification_name
        return "db/migrate" if specification_name.nil? || specification_name == "ActiveRecord::Base"

        "db/#{specification_name.underscore.tr("/", "_")}_migrate"
      end

      def model_connection_specification_name
        model_class = class_name.safe_constantize
        model_class&.connection_specification_name
      rescue StandardError
        nil
      end

      def log_table_name
        "#{table_name.singularize}_transitions"
      end

      def parent_class_name
        specification_name = model_connection_specification_name
        return "ApplicationRecord" if specification_name.nil? || specification_name == "ActiveRecord::Base"

        specification_name
      end

      def foreign_key_column
        "#{file_name}_id"
      end

      def migration_class_name
        "Create#{class_name}StateMachine"
      end

      def metadata_column_type
        adapter = ActiveRecord::Base.connection.adapter_name
        adapter.match?(/postg/i) ? "jsonb" : "json"
      rescue ActiveRecord::ActiveRecordError
        "jsonb"
      end
    end
  end
end
