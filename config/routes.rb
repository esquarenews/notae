require "sidekiq/web" if Rails.env.development?

Rails.application.routes.draw do
  mount ActionCable.server => "/cable"

  devise_for :users, controllers: {
    sessions: "users/sessions"
  }
  root "home#index"

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  resources :workspaces, only: %i[new create]

  scope "w/:workspace_slug" do
    get "/", to: "workspace_home#show", as: :workspace
    get "meetings", to: "meetings#show", as: :workspace_meetings
    get "meetings/status", to: "meetings#status", as: :workspace_meetings_status
    get "search", to: "searches#index", as: :workspace_search
    get "ai-conversation-history", to: "ai_conversation_histories#show", as: :workspace_ai_conversation_history
    get "library", to: "libraries#show", as: :workspace_library
    get "trash", to: "trash#show", as: :workspace_trash
    get "settings/general", to: "general_settings#show", as: :workspace_general_settings
    patch "settings/general", to: "general_settings#update"
    delete "settings/general", to: "general_settings#destroy"
    get "settings/people", to: "people_settings#show", as: :workspace_people_settings
    patch "settings/people", to: "people_settings#update"
    get "settings/import", to: "import_settings#show", as: :workspace_import_settings
    post "settings/import", to: "import_settings#create"
    get "settings/preferences", to: "preferences#show", as: :workspace_preferences
    patch "settings/preferences", to: "preferences#update"
    get "settings/notae-ai", to: "notae_ai_settings#show", as: :workspace_notae_ai_settings
    patch "settings/notae-ai", to: "notae_ai_settings#update"
    get "settings/ai-analytics", to: "ai_analytics_settings#show", as: :workspace_ai_analytics_settings
    get "settings/favicon-lab", to: "favicon_settings#show", as: :workspace_favicon_settings
    get "settings/connections", to: "connection_settings#show", as: :workspace_connection_settings
    patch "settings/connections", to: "connection_settings#update"
    get "settings/notifications", to: "notification_settings#show", as: :workspace_notification_settings
    patch "settings/notifications", to: "notification_settings#update"
    get "settings/kalendarium", to: "kalendarium_settings#show", as: :workspace_kalendarium_settings
    patch "settings/kalendarium", to: "kalendarium_settings#update"
    get "notifications", to: "notifications#index", as: :workspace_notifications
    patch "notifications/:id/read", to: "notifications#mark_read", as: :read_workspace_notification
    post "invitations", to: "invitations#create", as: :workspace_invitations
    get "kalendarium", to: "kalendarium#show", as: :kalendarium
    post "kalendarium/refresh", to: "kalendarium#refresh", as: :refresh_kalendarium
    resources :meeting_sessions, path: "meetings/sessions", only: %i[create update] do
      member do
        post :start
        post :stop
        post :reprocess
        patch :speakers
      end
    end
    resources :kalendarium_events, path: "kalendarium/events", only: %i[create update destroy]
    resources :kalendarium_projects, path: "kalendarium/projects", only: %i[create update destroy] do
      member do
        patch :archive
        patch :unarchive
      end
    end
    resources :kalendarium_connections, path: "kalendarium/connections", only: %i[create update destroy] do
      member do
        post :sync
      end
      collection do
        get :google_authorize
        get :google_callback
        get :icloud_callback
      end
    end
    resources :kalendarium_calendars, path: "kalendarium/calendars", only: %i[update]
    resources :kalendarium_write_proposals, path: "kalendarium/write_proposals", only: %i[create] do
      member do
        post :confirm
        post :reject
      end
    end
    resources :memberships, only: :update
    resources :databases, only: %i[show create update destroy] do
      member do
        post :duplicate
        post :kanbanize
        patch :archive
        patch :restore
        patch :permissions
        get :export_csv
      end
      resource :favorite, only: %i[create destroy], controller: "database_favorites"
      resources :database_views, only: %i[create update]
      patch "database_views/:id/default", to: "database_views#set_default", as: :default_database_view
      resources :db_properties, only: %i[create destroy]
      resources :db_rows, only: %i[create update destroy] do
        member do
          patch :move
          post :duplicate
          patch :restore
        end
      end
      resources :share_links, only: %i[create destroy], controller: "database_share_links"
      resources :comments, only: :create, controller: "database_comments" do
        member do
          patch :resolve
          patch :unresolve
        end
      end
      resources :db_cells, only: :update
    end

    resources :pages, only: %i[show create update destroy] do
      resource :favorite, only: %i[create destroy], controller: "page_favorites"
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
    get "join/:token", to: "workspace_join_links#show", as: :workspace_join_link
    post "ai-assistant", to: "ai_assistant#create", as: :workspace_ai_assistant
  end

  namespace :api do
    namespace :v1 do
      scope "workspaces/:workspace_slug" do
        resources :pages, only: %i[index show create update] do
          resources :blocks, only: %i[index show create update]
        end
        resources :databases, only: %i[index show create update]
        namespace :kalendarium do
          resources :calendars, only: :index
          resources :events, only: :index
          resources :write_proposals, only: :create do
            member do
              post :confirm
              post :reject
            end
          end
        end
        namespace :meetings do
          resources :sessions, only: %i[index show] do
            member do
              get :transcript
            end
          end
        end
      end
    end
  end

  get "invitations/:token", to: "invitations#show", as: :invitation
  post "invitations/:token/accept", to: "invitations#accept", as: :accept_invitation
  get "s/:token", to: "public/pages#show", as: :public_share
  get "g/:token", to: "public/databases#show", as: :public_database_share
  get "kalendarium/google/callback", to: "kalendarium_connections#google_callback", as: :kalendarium_google_callback

  namespace :internal do
    resources :meeting_bot_runs, only: [] do
      collection do
        post :claim
      end
      member do
        post :heartbeat
        post :upload_complete
        post :failed
      end
    end
  end

  mount Sidekiq::Web => "/sidekiq" if Rails.env.development?
end
