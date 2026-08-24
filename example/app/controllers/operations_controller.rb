# frozen_string_literal: true

# The one page with a real user for a feed: an operator reading "what
# happened", refusals included. The word "telemetry" stays out of the UI —
# this is an Operations log, not a metrics showcase.
class OperationsController < ApplicationController
  def index
    @entries = OperationEntry.feed
  end
end
