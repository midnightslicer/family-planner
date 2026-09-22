Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors.
  get "up" => "rails/health#show", as: :rails_health_check

  # First-run setup wizard (also the target of the first-run gate)
  get   "setup",              to: "setup#show",           as: :setup
  patch "setup/settings",     to: "setup#update_settings", as: :setup_settings
  post  "setup/test_email",   to: "setup#test_email",     as: :setup_test_email
  get   "setup/account",      to: "setup#account",        as: :setup_account
  post  "setup/account",      to: "setup#create_account"

  # Devise — registrations overridden for invite-only signup
  devise_for :users, controllers: { registrations: "registrations" }

  # Public invitation join flow
  get  "invitations/:token",      to: "invitations#show", as: :invitation
  post "invitations/:token/join", to: "invitations#join", as: :join_invitation

  # Household switching + card fragment + SSE stream (auth via controller) + public wall
  post "switch_household",     to: "households#switch", as: :switch_household
  get  "households/:id/stream", to: "households#stream", as: :household_stream
  get  "households/:id/cards/:user_id", to: "households#card", as: :household_card, constraints: ->(req) { req.format == :html }
  get  "h/:dashboard_token",    to: "walls#show",       as: :wall

  # Authenticated app
  root to: "dashboards#show", as: :dashboard_root
  get "dashboard", to: "dashboards#show", as: :dashboard
  resources :tasks do
    member do
      post :start
      post :complete
      post :cancel
    end
  end

  # Admin namespace (admin check in Admin::BaseController)
  namespace :admin do
    root to: "households#index", as: :root
    resources :households, only: [:index, :create, :edit, :update, :destroy]
    resources :invitations, only: [:index, :new, :create, :destroy] do
      member do
        post :resend
      end
    end
    resource :settings, only: [:show, :update] do
      collection do
        post :test_email
      end
    end
    get   "profile", to: "profiles#edit",   as: :profile
    patch "profile", to: "profiles#update", as: :update_profile
  end
end