# frozen_string_literal: true

module Admin
  # The one feed with a real user: an operator reading "what happened",
  # refusals included. The word "telemetry" stays out of the UI — this is
  # an Operations log, not a metrics showcase.
  class OperationsController < BaseController
    def index
      @entries = OperationEntry.feed
    end
  end
end
