Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors.
  get "up" => "rails/health#show", as: :rails_health_check

  # Installable app: manifest and service worker (PwaController, no sign-in).
  get "manifest.webmanifest", to: "pwa#manifest",       as: :pwa_manifest,       format: false
  get "service-worker.js",    to: "pwa#service_worker", as: :pwa_service_worker, format: false

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

  # Household switching + the wall (live updates arrive over Action Cable)
  post "switch_household",  to: "households#switch", as: :switch_household
  get  "h/:slug", to: "walls#show",       as: :wall

  # Authenticated app
  root to: "dashboards#show", as: :dashboard_root
  get  "dashboard", to: "dashboards#show", as: :dashboard
  post "dashboard/dismiss_checklist", to: "dashboards#dismiss_checklist", as: :dismiss_checklist
  post "getting_started/skip/:step", to: "dashboards#skip_step", as: :skip_checklist_step
  resources :tasks do
    member do
      post :start
      post :pause
      post :complete
      post :cancel
      post :accept
      post :decline
    end
  end

  # Pets and the places they (and people) can be. The two batch flows come
  # before `resources :pets` so "where" and "feed" aren't read as pet ids.
  get  "pets/where", to: "pet_locations#new",    as: :new_pet_location
  post "pets/where", to: "pet_locations#create", as: :pet_locations
  get  "pets/feed",  to: "feedings#new",         as: :new_feeding
  post "pets/feed",  to: "feedings#create",      as: :feedings
  resources :feedings, only: :destroy
  resources :location_reports, only: :destroy
  resources :pets do
    member do
      post :away
      post :back
    end
    # Follow / unfollow: notifications when it's moved or fed.
    resource :subscription, only: [:create, :destroy], controller: "pet_subscriptions"
  end
  resources :locations, except: :show
  # Your regular work hours (optional) and days off.
  resource :work_schedule, only: [:edit, :update]
  post   "days_off",     to: "days_off#create",  as: :days_off
  delete "days_off/:id", to: "days_off#destroy", as: :day_off
  resources :people, only: :show do
    # Admins: someone else's profile (ManagesPerson).
    resource :profile, only: [:edit, :update], controller: "person_profiles"
  end
  post "people/me/location", to: "people#locate", as: :locate_me

  # Devices that get push notifications (always the signed-in person's own).
  resources :push_subscriptions, only: [:create, :destroy] do
    collection do
      post :test
      post :unsubscribe
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
      resources :memberships, only: [:update, :destroy]
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
