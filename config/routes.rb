require "sidekiq/web" if Rails.env.development?

Rails.application.routes.draw do
  devise_for :users
  root "home#index"

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  resources :workspaces, only: %i[new create]
  get "w/:workspace_slug", to: "workspace_home#show", as: :workspace
  post "w/:workspace_slug/invitations", to: "invitations#create", as: :workspace_invitations

  get "invitations/:token", to: "invitations#show", as: :invitation
  post "invitations/:token/accept", to: "invitations#accept", as: :accept_invitation

  mount Sidekiq::Web => "/sidekiq" if Rails.env.development?
end
