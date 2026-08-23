# frozen_string_literal: true

module Statecraft
  # The model-side macro. `state_machine OrderFlow, ...` mounts a compiled
  # machine onto an ActiveRecord model: resolves the log class (convention
  # `<base_class>Transition`, overridable via log:), runs the mounting-time
  # checks (AlreadyMounted, composite primary keys, connection-class identity),
  # finalizes the machine, verifies helper and scope name conflicts, generates
  # scopes, and defines the reading surface (history, last_transition,
  # in_state?). Everything internal goes through base_class.
  module Mounting
    Configuration = Struct.new(
      :machine_class, :log_class, :column, :changed_at_column, :touch, :helpers, :scopes,
      :log_foreign_key,
      keyword_init: true
    )

    def state_machine(machine_class, log: nil, column: :state, changed_at: false, touch: true,
                      helpers: false, scopes: false)
      Builder.new(
        model: self, machine_class: machine_class, log: log, column: column,
        changed_at: changed_at, touch: touch, helpers: helpers, scopes: scopes
      ).mount
    end

    # Performs the mounting steps in threshold order. Every check here works on
    # class hierarchies only — never on the schema and never on a live
    # connection, so mounting is safe at load time.
    class Builder
      def initialize(model:, machine_class:, log:, column:, changed_at:, touch:, helpers:, scopes:)
        @model = model
        @machine_class = machine_class
        @log_option = log
        @column = column
        @changed_at = changed_at
        @touch = touch
        @helpers = helpers
        @scopes = scopes
      end

      def mount
        assert_not_mounted
        assert_single_column_primary_key
        log_class = resolve_log_class
        assert_shared_connection_class(log_class)
        graph = machine_class.finalize!
        assert_no_verb_conflicts(graph)
        assert_no_scope_conflicts(graph)
        configuration = build_configuration(log_class)
        store_configuration(configuration)
        define_scopes(graph, configuration)
        define_reading_surface
        model.include(Pipeline::Surface)
        configuration
      end

      private

      attr_reader :model, :machine_class

      def assert_not_mounted
        raise AlreadyMounted.new(model: model) if model.respond_to?(:statecraft_mounting)
      end

      def assert_single_column_primary_key
        raise CompositePrimaryKeyUnsupported.new(model: model) if model.primary_key.is_a?(Array)
      end

      def resolve_log_class
        return @log_option if @log_option

        conventional_name = "#{model.base_class.name}Transition"
        begin
          Object.const_get(conventional_name)
        rescue NameError
          raise CompilationError,
                "log class #{conventional_name} not found for #{model.name}: " \
                "create it or pass log: explicitly"
        end
      end

      def assert_shared_connection_class(log_class)
        return if model.connection_specification_name == log_class.connection_specification_name

        raise ConnectionMismatch.new(model: model, log_class: log_class)
      end

      def assert_no_verb_conflicts(graph)
        return unless @helpers

        graph.events.each_key do |event_name|
          verb_names(event_name).each do |verb|
            next unless model.method_defined?(verb) || model.private_method_defined?(verb)

            raise CompilationError,
                  "helper #{verb} for event #{event_name.inspect} conflicts with an existing " \
                  "instance method on #{model.name}"
          end
        end
      end

      def assert_no_scope_conflicts(graph)
        return unless @scopes

        graph.states.each do |state_name|
          next unless model.respond_to?(state_name, true)

          raise CompilationError,
                "scope #{state_name} conflicts with an existing class method on #{model.name}"
        end
      end

      def verb_names(event_name)
        ["#{event_name}!", event_name.to_s, "may_#{event_name}?"]
      end

      def build_configuration(log_class)
        Configuration.new(
          machine_class: machine_class,
          log_class: log_class,
          column: @column.to_sym,
          changed_at_column: resolve_changed_at_column,
          touch: @touch,
          helpers: @helpers,
          scopes: @scopes,
          log_foreign_key: model.base_class.name.foreign_key.to_sym
        ).freeze
      end

      def resolve_changed_at_column
        case @changed_at
        when false then nil
        when true then :"#{@column}_changed_at"
        else @changed_at.to_sym
        end
      end

      def store_configuration(configuration)
        model.define_singleton_method(:statecraft_mounting) { configuration }
      end

      def define_scopes(graph, configuration)
        return unless configuration.scopes

        column = configuration.column
        graph.states.each do |state_name|
          model.scope state_name, -> { where(column => state_name.to_s) }
        end
      end

      def define_reading_surface
        reading_surface = Module.new do
          define_method(:history) do
            config = self.class.statecraft_mounting
            config.log_class.where(config.log_foreign_key => id).order(:id)
          end

          define_method(:last_transition) do
            history.last
          end

          define_method(:in_state?) do |state_name|
            config = self.class.statecraft_mounting
            self[config.column].to_s == state_name.to_s
          end
        end
        model.include(reading_surface)
      end
    end
  end
end
