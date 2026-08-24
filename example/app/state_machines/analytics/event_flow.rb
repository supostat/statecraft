# frozen_string_literal: true

module Analytics
  class EventFlow
    include Statecraft::Machine

    state :recorded, initial: true
    state :archived

    event :archive, from: :recorded, to: :archived
  end
end
