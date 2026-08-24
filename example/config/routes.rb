# frozen_string_literal: true

Rails.application.routes.draw do
  # The chapters mount their own resources; the root always lands on Orders.
  root to: redirect("/orders")

  # admin is a route namespace, not a security boundary: the harness has no
  # users and no auth by design (see README).
end
