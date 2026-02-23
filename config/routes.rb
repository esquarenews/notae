require "sidekiq/web" if Rails.env.development?

Rails.application.routes.draw do
  devise_for :users
  root "home#index"

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  resources :workspaces, only: %i[new create]

  scope "w/:workspace_slug" do
    get "/", to: "workspace_home#show", as: :workspace
    get "search", to: "searches#index", as: :workspace_search
    get "notifications", to: "notifications#index", as: :workspace_notifications
    patch "notifications/:id/read", to: "notifications#mark_read", as: :read_workspace_notification
    post "invitations", to: "invitations#create", as: :workspace_invitations
    resources :memberships, only: :update

    resources :pages, only: %i[show create] do
      resources :comments, only: :create do
        member do
          patch :resolve
          patch :unresolve
        end
      end

      member do
        patch :archive
        patch :restore
        patch :permissions
      end

      resources :blocks, only: %i[create update] do
        resources :comments, only: :create do
          member do
            patch :resolve
            patch :unresolve
          end
        end

        member do
          patch :attach
          get :download
          patch :reorder
          patch :archive
          patch :restore
        end
      end
    end
  end

  get "invitations/:token", to: "invitations#show", as: :invitation
  post "invitations/:token/accept", to: "invitations#accept", as: :accept_invitation

  mount Sidekiq::Web => "/sidekiq" if Rails.env.development?
end
