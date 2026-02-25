require "sidekiq/web" if Rails.env.development?

Rails.application.routes.draw do
  mount ActionCable.server => "/cable"

  devise_for :users
  root "home#index"

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  resources :workspaces, only: %i[new create]

  scope "w/:workspace_slug" do
    get "/", to: "workspace_home#show", as: :workspace
    get "search", to: "searches#index", as: :workspace_search
    get "settings/preferences", to: "preferences#show", as: :workspace_preferences
    patch "settings/preferences", to: "preferences#update"
    get "settings/connections", to: "connection_settings#show", as: :workspace_connection_settings
    patch "settings/connections", to: "connection_settings#update"
    get "settings/notifications", to: "notification_settings#show", as: :workspace_notification_settings
    patch "settings/notifications", to: "notification_settings#update"
    get "notifications", to: "notifications#index", as: :workspace_notifications
    patch "notifications/:id/read", to: "notifications#mark_read", as: :read_workspace_notification
    post "invitations", to: "invitations#create", as: :workspace_invitations
    resources :memberships, only: :update
    resources :databases, only: %i[show create] do
      resources :database_views, only: %i[create update]
      patch "database_views/:id/default", to: "database_views#set_default", as: :default_database_view
      resources :db_properties, only: %i[create destroy]
      resources :db_rows, only: :create do
        member do
          patch :move
        end
      end
      resources :db_cells, only: :update
    end

    resources :pages, only: %i[show create update] do
      resources :share_links, only: %i[create destroy]

      resources :comments, only: :create do
        member do
          patch :resolve
          patch :unresolve
        end
      end

      member do
        post :duplicate
        patch :archive
        patch :restore
        patch :permissions
        get :export_markdown, to: "page_exports#markdown"
        post :export_zip, to: "page_exports#create"
        post :save_as_template, to: "page_templates#create"
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
          post :command
        end
      end
    end

    resources :page_templates, only: [] do
      member do
        post :instantiate
      end
    end

    get "exports/:token", to: "page_exports#download", as: :workspace_export
  end

  namespace :api do
    namespace :v1 do
      scope "workspaces/:workspace_slug" do
        resources :pages, only: %i[index show create update] do
          resources :blocks, only: %i[index show create update]
        end
        resources :databases, only: %i[index show create update]
      end
    end
  end

  get "invitations/:token", to: "invitations#show", as: :invitation
  post "invitations/:token/accept", to: "invitations#accept", as: :accept_invitation
  get "s/:token", to: "public/pages#show", as: :public_share

  mount Sidekiq::Web => "/sidekiq" if Rails.env.development?
end
