# frozen_string_literal: true

# The hermetic tenant of the second database: everything living in analytics
# descends from this base and never shares a connection with the primary.
class AnalyticsRecord < ActiveRecord::Base
  self.abstract_class = true

  connects_to database: { writing: :analytics }
end
