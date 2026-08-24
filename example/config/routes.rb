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

  post "switch_user", to: "switch_users#create"

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

  # The old public address now belongs to the customer.
  get "orders", to: redirect("/my/orders")

  # admin is a route namespace, not a security boundary: the harness has no
  # users and no auth by design (see README). Everything the gem can show —
  # panels, history, bypass, the feed — lives here, where operators work.
  namespace :admin do
    resources :orders, only: %i[index show] do
      member do
        post :pay
        post :cancel
        post :refund
        post :preview
        post :admin_override
        post :bypass_cancel
        post :create_shipment
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
  end
end
