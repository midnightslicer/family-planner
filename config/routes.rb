Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors.
  get "up" => "rails/health#show", as: :rails_health_check

  # First-run setup (also the target of the first-run gate)
  get  "setup",                 to: "setup#show",            as: :setup
  post "setup",                 to: "setup#create"
  post "setup/unlock",          to: "setup#unlock",          as: :setup_unlock
  post "setup/passkey_options", to: "setup#passkey_options", as: :setup_passkey_options

  # Sign-in: Devise password flow (no public sign-up), then an optional
  # authenticator-code step; or a passkey.
  devise_for :users, skip: :registrations,
                     controllers: { sessions: "users/sessions", passwords: "users/passwords" }
  get  "users/two_factor",        to: "users/two_factor#show",            as: :user_two_factor
  post "users/two_factor",        to: "users/two_factor#create"
  post "users/passkey/options",   to: "users/passkey_sessions#options",   as: :user_passkey_options
  post "users/passkey",           to: "users/passkey_sessions#create",    as: :user_passkey_session

  # Public invitation join flow
  get  "invitations/:token",                 to: "invitations#show",            as: :invitation
  post "invitations/:token/join",            to: "invitations#join",            as: :join_invitation
  post "invitations/:token/accept",          to: "invitations#accept",          as: :accept_invitation
  post "invitations/:token/passkey_options", to: "invitations#passkey_options", as: :invitation_passkey_options

  # Household switching + public wall (live updates arrive over Action Cable)
  post "switch_household",  to: "households#switch", as: :switch_household
  get  "h/:dashboard_token", to: "walls#show",       as: :wall

  # Authenticated app
  root to: "dashboards#show", as: :dashboard_root
  get  "dashboard", to: "dashboards#show", as: :dashboard
  post "dashboard/dismiss_checklist", to: "dashboards#dismiss_checklist", as: :dismiss_checklist
  resources :tasks do
    member do
      post :start
      post :pause
      post :complete
      post :cancel
    end
  end

  # Everyone's own account: profile, password, passkeys, two-step verification
  namespace :account do
    root to: "profiles#show"
    resource :profile, only: :update
    resource :password, only: :update
    resources :passkeys, only: [:create, :update, :destroy] do
      post :options, on: :collection
    end
    resource :two_factor, only: [:new, :create, :destroy], controller: "two_factor"
    resource :recovery_codes, only: :create
  end

  # Admin namespace (admin check in Admin::BaseController)
  namespace :admin do
    root to: "households#index", as: :root
    resources :households, only: [:index, :create, :edit, :update, :destroy] do
      post :regenerate_wall_link, on: :member
      resources :memberships, only: :destroy
    end
    resources :invitations, only: [:index, :new, :create, :show, :destroy] do
      post :resend, on: :member
    end
    resources :users, only: [:index, :update, :destroy] do
      post :reset_security, on: :member
      post :password_link, on: :member
    end
    resource :settings, only: [:show, :update] do
      post :test_email, on: :collection
    end
  end
end
