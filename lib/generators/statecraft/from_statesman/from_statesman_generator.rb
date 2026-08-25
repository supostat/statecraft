# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

module Statecraft
  module Generators
    # `rails generate statecraft:from_statesman Order [OrderStateMachine]` —
    # the migration path off statesman. Reads the live statesman machine
    # through reflection (states, initial state, transition graph, guard
    # locations), generates the in-place conversion migration that turns the
    # statesman transitions table into this gem's log, a machine skeleton
    # whose events and guards are left for the human, and mounts the machine
    # into the model. The statesman class itself is never loaded by name
    # magic beyond the optional second argument's default.
    class FromStatesmanGenerator < Rails::Generators::NamedBase
      include ActiveRecord::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      argument :statesman_machine_name, type: :string, required: false,
                                        desc: "The statesman machine class (default: <Model>StateMachine)"

      def load_statesman_machine
        @statesman_machine = resolve_statesman_machine
        @initial_state = @statesman_machine.initial_state
        return unless @initial_state.nil?

        raise Thor::Error, "#{statesman_class_name} declares no initial state; " \
                           "statecraft requires exactly one — declare `state ..., initial: true` first"
      end

      def create_application_machine
        application_machine_path = "app/state_machines/application_machine.rb"
        return if File.exist?(File.join(destination_root, application_machine_path))

        template "application_machine.rb.tt", application_machine_path
      end

      def create_machine_skeleton
        template "machine_from_statesman.rb.tt", "app/state_machines/#{file_path}_flow.rb"
      end

      def mount_model
        unless File.exist?(File.join(destination_root, model_file))
          say_status :skip, "#{model_file} not found — mount the machine yourself: #{mounting_line.strip}", :yellow
          return
        end

        inject_into_class model_file, class_name, mounting_line
      end

      def create_conversion_migration
        migration_template "convert_transitions_migration.rb.tt",
                           "#{migration_directory}/convert_#{migration_slug}_transitions_to_statecraft.rb"
      end

      def print_cleanup_instructions
        say "\nAfter running the migration, finish the move by hand:", :green
        say "  * #{log_class_name}: drop `include Statesman::Adapters::ActiveRecordTransition` and"
        say "    the `after_destroy :update_most_recent` callback (they read dropped columns);"
        say "    consider adding `def readonly? = persisted?` — the pipeline inserts around it."
        say "  * #{class_name}: drop `include Statesman::Adapters::ActiveRecordQueries` and the"
        say "    state_machine/transition helper methods that wrapped statesman."
        say "  * Delete the `Statesman.configure` initializer once no machine is left."
        say "  * Name your events in app/state_machines/#{file_path}_flow.rb — statesman had none."
      end

      private

      def resolve_statesman_machine
        machine_class = statesman_class_name.safe_constantize
        if machine_class.nil?
          raise Thor::Error, "statesman machine class #{statesman_class_name} not found — " \
                             "pass it explicitly: rails g statecraft:from_statesman #{name} YourMachineClass"
        end

        unless machine_class.respond_to?(:states) && machine_class.respond_to?(:successors)
          raise Thor::Error, "#{statesman_class_name} does not look like a statesman machine " \
                             "(no .states/.successors); note that statesman graphs are not inherited — " \
                             "point at the class that declares the DSL"
        end

        machine_class
      end

      def statesman_class_name
        statesman_machine_name || "#{class_name}StateMachine"
      end

      attr_reader :initial_state

      def states
        @statesman_machine.states.map(&:to_s)
      end

      # statesman accumulates successors without deduplication and statecraft
      # refuses a duplicate edge at compile time, so uniq is load-bearing.
      def edges
        @statesman_machine.successors.flat_map do |from, destinations|
          Array(destinations).map { |to| [from.to_s, to.to_s] }
        end.uniq
      end

      def guard_notes
        return [] unless @statesman_machine.respond_to?(:callbacks)

        Array(@statesman_machine.callbacks[:guards]).map do |guard|
          origin = guard.callback.respond_to?(:source_location) ? guard.callback.source_location&.join(":") : nil
          from_label = guard.from || "any"
          to_label = Array(guard.to).empty? ? "any" : Array(guard.to).join("/")
          note = "#{from_label} -> #{to_label}"
          origin ? "#{note} (defined at #{origin})" : note
        end
      end

      def mounting_line
        "  state_machine #{class_name}Flow, changed_at: true, helpers: true, scopes: true\n"
      end

      def model_file
        "app/models/#{file_path}.rb"
      end

      def model_class
        class_name.safe_constantize
      end

      def table_name
        @table_name ||= model_class.respond_to?(:table_name) ? model_class.table_name : super
      end

      def log_table_name
        "#{table_name.singularize}_transitions"
      end

      def log_class_name
        "#{class_name}Transition"
      end

      def foreign_key_column
        "#{file_name}_id"
      end

      def migration_directory
        db_config = model_class.respond_to?(:connection_db_config) && model_class.connection_db_config
        configured = db_config && Array(db_config.migrations_paths).first
        configured || "db/migrate"
      end

      def migration_slug
        file_path.tr("/", "_")
      end

      def migration_class_name
        "Convert#{migration_slug.camelize}TransitionsToStatecraft"
      end
    end
  end
end
