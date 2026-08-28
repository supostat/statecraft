# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

module Statecraft
  module Generators
    # `rails generate statecraft:from_aasm Order [machine_name]` — the door
    # off aasm. Reads the live aasm machine through reflection (states, the
    # initial state, real event names, the state column and the symbol
    # guards), generates the machine skeleton, the log table migration and
    # the mounting line. aasm keeps state in a column already, so nothing is
    # backfilled: the conversion adds the history aasm never had.
    class FromAasmGenerator < Rails::Generators::NamedBase
      include ActiveRecord::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      argument :aasm_machine_name, type: :string, required: false,
                                   desc: "The named aasm machine (default: the unnamed one)"

      def load_aasm_machine
        @aasm_machine = resolve_aasm_machine
        assert_graph_present
        assert_no_branching_events
      end

      def create_application_machine
        application_machine_path = "app/state_machines/application_machine.rb"
        return if File.exist?(File.join(destination_root, application_machine_path))

        template "application_machine.rb.tt", application_machine_path
      end

      def create_machine_skeleton
        template "machine_from_aasm.rb.tt", "app/state_machines/#{file_path}_flow.rb"
      end

      def mount_model
        unless File.exist?(File.join(destination_root, model_file))
          say_status :skip, "#{model_file} not found — mount the machine yourself: #{mounting_line.strip}", :yellow
          return
        end

        inject_into_class model_file, class_name, mounting_line
      end

      def create_log_migration
        migration_template "create_log_table.rb.tt",
                           "#{migration_directory}/create_#{migration_slug}_transitions.rb"
      end

      def print_cleanup_instructions
        say "\nOne migration: it creates the log table aasm never had and indexes " \
            "the existing #{state_column} column.", :green
        say "The column itself is left alone — NOT NULL, a default and a CHECK on a live"
        say "table are locks and legacy-row explosions; the migration header carries the recipe."
        say "\nAfter it runs, finish the move by hand:", :green
        say "  * #{class_name}: drop `include AASM` and the whole `aasm do ... end` block."
        say "  * Event calls keep their names with helpers: true (`order.pay!`), but a losing"
        say "    race now raises TransitionConflict instead of quietly answering false."
        say "  * aasm state predicates (`order.paid?`) are not generated: use `in_state?(:paid)`"
        say "    or the `#{class_name}.paid` scope."
        say "  * Guards that were lambdas are TODO comments in the skeleton — port them by hand."
      end

      private

      def resolve_aasm_machine
        unless model_class.respond_to?(:aasm)
          raise Thor::Error, "#{class_name} does not respond to .aasm — " \
                             "point the generator at the model that includes AASM"
        end

        machine = aasm_machine_name ? model_class.aasm(aasm_machine_name.to_sym) : model_class.aasm
        unless machine.respond_to?(:states) && machine.respond_to?(:events)
          raise Thor::Error, "#{class_name}.aasm does not look like an aasm machine (no .states/.events)"
        end

        machine
      end

      def model_class
        @model_class ||= class_name.safe_constantize ||
                         raise(Thor::Error, "model class #{class_name} not found — " \
                                            "the generator reads the live aasm machine off it")
      end

      # A model with named machines answers the unnamed `.aasm` with the
      # :default machine, which holds no states at all — a silently empty
      # graph. Name the machines instead of generating a skeleton of nothing.
      def assert_graph_present
        return unless states.empty?

        raise Thor::Error, "#{class_name}'s #{machine_label} declares no states#{named_machines_hint}"
      end

      def named_machines_hint
        names = declared_machine_names - ["default"]
        return "" if names.empty?

        " — it declares named machines: #{names.join(", ")}; " \
          "pass one: rails g statecraft:from_aasm #{name} #{names.first}"
      end

      def declared_machine_names
        store = defined?(AASM::StateMachineStore) && AASM::StateMachineStore.fetch(model_class)
        store.respond_to?(:machine_names) ? store.machine_names.map(&:to_s) : []
      rescue StandardError
        []
      end

      # aasm picks the first transition of an event whose guard passes, so one
      # event may branch from a single state; statecraft compiles an event as a
      # partial function (from is unique within an event) and refuses such a
      # graph. The split is a domain decision, so the door stops here.
      def assert_no_branching_events
        branching = event_descriptors.filter_map do |event|
          froms = event[:transitions].map { |transition| transition[:from] }
          duplicated = froms.tally.select { |_from, count| count > 1 }.keys
          "#{event[:name]} (from #{duplicated.join(", ")})" unless duplicated.empty?
        end
        return if branching.empty?

        raise Thor::Error,
              "these aasm events branch from one state: #{branching.join("; ")}. " \
              "statecraft makes an event a partial function — within one event, from is unique. " \
              "Split each into two named events (the pay / fail_payment pattern) in aasm first, " \
              "then rerun this generator."
      end

      def event_descriptors
        @event_descriptors ||= @aasm_machine.events.map do |event|
          {
            name: event.name,
            transitions: event.transitions.map { |transition| describe_transition(event, transition) }
          }
        end
      end

      def describe_transition(event, transition)
        options = transition.respond_to?(:opts) ? transition.opts : {}
        { from: transition.from, to: transition.to, guard: guard_descriptor(event, transition, options) }
      end

      # aasm spells the record-level guard three ways and calls it on the
      # record; statecraft's record_guard: is the same nature (arity 1) but
      # resolves on the machine, so every symbol becomes a one-line delegate.
      # A lambda carries its own closure and cannot be moved — it is reported.
      def guard_descriptor(event, transition, options)
        positive = options[:guard] || options[:if]
        negative = options[:unless]
        return symbol_guard(positive, negated: false) if positive.is_a?(Symbol)
        return symbol_guard(negative, negated: true) if negative.is_a?(Symbol)

        lambda_note(event, transition, positive || negative)
      end

      def symbol_guard(name, negated:)
        { kind: :delegate, source: name, method_name: negated ? "not_#{name.to_s.delete_suffix("?")}?" : name.to_s,
          negated: negated }
      end

      def lambda_note(event, transition, callable)
        return nil if callable.nil?

        location = callable.respond_to?(:source_location) ? callable.source_location&.join(":") : nil
        origin = location ? " — defined at #{location}" : ""
        { kind: :todo, note: "#{event.name} (#{transition.from} -> #{transition.to})#{origin}" }
      end

      def states
        @states ||= @aasm_machine.states.map { |state| state.name.to_s }
      end

      def initial_state
        @aasm_machine.initial_state.to_s
      end

      def events
        event_descriptors.flat_map do |event|
          event[:transitions].map do |transition|
            { name: event[:name], from: transition[:from], to: transition[:to],
              guard: delegate_guard(transition) }
          end
        end
      end

      def guard_delegates
        events.filter_map { |event| event[:guard] }.uniq { |guard| guard[:method_name] }
      end

      def guard_todos
        all_guards.filter_map { |guard| guard[:note] if guard[:kind] == :todo }
      end

      def delegate_guard(transition)
        guard = transition[:guard]
        guard if guard && guard[:kind] == :delegate
      end

      def all_guards
        event_descriptors.flat_map { |event| event[:transitions].filter_map { |t| t[:guard] } }
      end

      def state_column
        @aasm_machine.respond_to?(:attribute_name) ? @aasm_machine.attribute_name.to_s : "state"
      end

      def machine_label
        aasm_machine_name ? "aasm machine #{aasm_machine_name}" : "unnamed aasm machine"
      end

      def mounting_line
        column = state_column == "state" ? "" : "column: :#{state_column}, "
        "  state_machine #{class_name}Flow, #{column}changed_at: true, helpers: true, scopes: true\n"
      end

      def model_file
        "app/models/#{file_path}.rb"
      end

      def table_name
        @table_name ||= model_class.respond_to?(:table_name) ? model_class.table_name : super
      end

      def log_table_name
        "#{table_name.singularize}_transitions"
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
        "Create#{migration_slug.camelize}Transitions"
      end
    end
  end
end
