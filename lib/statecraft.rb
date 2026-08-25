# frozen_string_literal: true

require "active_support"
require "active_record"

require_relative "statecraft/version"
require_relative "statecraft/errors"
require_relative "statecraft/warnings"
require_relative "statecraft/instrumentation"
require_relative "statecraft/machine"
require_relative "statecraft/metadata"
require_relative "statecraft/pipeline/edge_resolution"
require_relative "statecraft/pipeline"
require_relative "statecraft/pipeline/surface"
require_relative "statecraft/introspection"
require_relative "statecraft/diagram"
require_relative "statecraft/mounting"

ActiveSupport.on_load(:active_record) do
  extend Statecraft::Mounting
end
