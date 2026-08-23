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
    # ApplicationMachine parent. The migration lands in the migration path
    # configured for the model's database, so multi-database apps get it next
    # to their model.
    class MachineGenerator < Rails::Generators::NamedBase
      include ActiveRecord::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      def detect_model_presence
        @existing_model = File.exist?(File.join(destination_root, model_file))
      end

      def create_application_machine
        application_machine_path = "app/state_machines/application_machine.rb"
        return if File.exist?(File.join(destination_root, application_machine_path))

        template "application_machine.rb.tt", application_machine_path
      end

      def create_namespace_module
        return if class_path.empty? || existing_model?

        module_file = "app/models/#{class_path.join("/")}.rb"
        return if File.exist?(File.join(destination_root, module_file))

        template "namespace_module.rb.tt", module_file
      end

      def create_machine_class
        template "machine.rb.tt", "app/state_machines/#{file_path}_flow.rb"
      end

      def create_log_model
        template "log_model.rb.tt", "app/models/#{file_path}_transition.rb"
      end

      def create_or_mount_model
        if existing_model?
          inject_into_class model_file, mounting_target_class, mounting_line
        else
          template "model.rb.tt", model_file
        end
      end

      def create_migration_file
        migration_source = existing_model? ? "add_migration.rb.tt" : "create_migration.rb.tt"
        migration_template migration_source,
                           "#{migration_directory}/create_#{migration_slug}_state_machine.rb"
      end

      private

      def existing_model?
        @existing_model
      end

      def model_file
        "app/models/#{file_path}.rb"
      end

      def mounting_line
        "  state_machine #{class_name}Flow, changed_at: true, helpers: true, scopes: true\n"
      end

      # inject_into_class matches the literal `class <name>` line, so the name
      # must follow the style the model file actually uses: the full constant
      # for the compact `class Shop::Order` style, the demodulized one for
      # `module Shop / class Order` nesting.
      def mounting_target_class
        return class_name if class_path.empty?

        model_source = File.read(File.join(destination_root, model_file))
        model_source.match?(/class #{class_name}\b/) ? class_name : class_name.demodulize
      end

      # Without a configured migrations_paths, `rails db:migrate` reads
      # db/migrate for every database — so that is the honest fallback.
      def migration_directory
        db_config = model_class&.connection_db_config
        configured = db_config && Array(db_config.migrations_paths).first
        configured || "db/migrate"
      end

      def model_class
        class_name.safe_constantize
      end

      # The generated model's table follows the loaded model when one exists;
      # otherwise the Rails naming convention for the argument, namespace
      # included (`Shop::Order` -> shop_orders, matching the generated
      # namespace module's table_name_prefix).
      def table_name
        @table_name ||= model_class ? model_class.table_name : super
      end

      def log_table_name
        "#{table_name.singularize}_transitions"
      end

      def parent_class_name
        specification_name = model_class&.connection_specification_name
        return "ApplicationRecord" if specification_name.nil? || specification_name == "ActiveRecord::Base"

        specification_name
      end

      def foreign_key_column
        "#{file_name}_id"
      end

      def migration_slug
        file_path.tr("/", "_")
      end

      def migration_class_name
        "Create#{migration_slug.camelize}StateMachine"
      end
    end
  end
end
