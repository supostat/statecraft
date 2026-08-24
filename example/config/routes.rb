# frozen_string_literal: true

Rails.application.routes.draw do
  # The storefront is the front door.
  root to: redirect("/products")

  resources :products, only: :index

  resource :cart, only: :show, controller: "carts" do
    post "add/:product_id", action: :add, as: :add_to
    post "remove/:product_id", action: :remove, as: :remove_from
  end

  get "checkout", to: "checkouts#new"
  post "checkout", to: "checkouts#create"

  # The customer's own orders: found by the session, described in human
  # words — the gem's vocabulary stays in the operator zone.
  namespace :my do
    resources :orders, only: %i[index show] do
      member do
        post :pay
        post :cancel
      end
    end
  end

  resources :orders, only: %i[index show] do
    member do
      post :pay
      post :cancel
      post :refund
      post :preview
    end
  end

  resources :payments, only: %i[index show] do
    member do
      post :capture
      post :save_and_capture
    end
  end

  resources :shipments, only: %i[index show] do
    member do
      post :pack
      post :ship
      post :deliver
    end
  end

  get "operations", to: "operations#index"

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
