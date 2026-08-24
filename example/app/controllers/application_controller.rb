# frozen_string_literal: true

class ApplicationController < ActionController::Base
  helper_method :current_user

  # No authentication by design: the current user is whoever the top-bar
  # switcher picked, defaulting to the seeded customer.
  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) ||
                      User.where(role: "user").order(:id).first
  end

  rescue_from CanCan::AccessDenied do
    redirect_to products_path,
                alert: "That area needs a different role — switch the user in the top bar."
  end

  # The staleness family heals in one place: both errors mean "the record
  # moved on while you were looking" — flash the gem's message, show the
  # fresh card. Guard refusals are NOT here: a refusal is local to its form.
  # Programmer errors (Dirty/Unsaved/Nested/ChainDepth) are not caught at
  # all — they belong to the error tracker.
  rescue_from Statecraft::InvalidTransition do |error|
    redirect_to stale_record_path(error.record),
                alert: "This action is no longer available: #{error.message}"
  end

  rescue_from Statecraft::TransitionConflict do |error|
    redirect_to stale_record_path(error.record),
                alert: "Another operator got there first — check and retry: #{error.message}"
  end

  private

  # The fresh operator card of whatever record went stale; base_class keeps
  # STI descendants on their parent's route. The customer zone overrides the
  # family with storefront language.
  def stale_record_path(record)
    url_for(controller: "/admin/#{record.class.base_class.name.tableize}",
            action: :show, id: record.id)
  end
end
