# frozen_string_literal: true

Rails.application.routes.draw do
  # The root always lands on Orders.
  root to: redirect("/orders")

  resources :orders, only: %i[index show] do
    member do
      post :pay
      post :cancel
      post :refund
      post :preview
    end
  end

  # admin is a route namespace, not a security boundary: the harness has no
  # users and no auth by design (see README).
  namespace :admin do
    resources :orders, only: :show do
      member do
        post :admin_override
        post :bypass_cancel
      end
    end
  end
end
