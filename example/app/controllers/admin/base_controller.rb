# frozen_string_literal: true

module Admin
  # The operator zone's doorway: entry itself is a permission. admin stays a
  # route namespace, not a security boundary — but the Ability decides who
  # works here.
  class BaseController < ApplicationController
    before_action { authorize! :access, :admin_zone }
  end
end
