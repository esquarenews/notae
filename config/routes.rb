require "sidekiq/web" if Rails.env.development?

Rails.application.routes.draw do
  mount ActionCable.server => "/cable"

  devise_for :users, controllers: {
    sessions: "users/sessions"
  }
  root "home#index"
  get "/app", to: "pwa#launch", as: :pwa_launch
  get "/app/notifications/:id", to: "pwa#notification_launch", as: :pwa_notification_launch
  get "/offline", to: "pwa#offline", as: :pwa_offline
  get "/manifest.webmanifest", to: "pwa#manifest", as: :pwa_manifest
  get "/service-worker.js", to: "pwa#service_worker", as: :pwa_service_worker
  resource :pwa_push_subscription, path: "pwa/push-subscription", only: %i[create destroy]

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
  post "webhooks/fat_zebra", to: "webhooks/fat_zebra#create", as: :fat_zebra_webhook

  namespace :admin do
    root "dashboard#show"
    resources :workspaces, only: %i[index show update] do
      member do
        patch :suspend
        patch :reactivate
      end
    end
    resources :users, only: %i[index show]
  end

  resources :workspaces, only: %i[new create]

  scope "w/:workspace_slug" do
    get "/", to: "workspace_home#show", as: :workspace
    get "meetings", to: "meetings#show", as: :workspace_meetings
    get "meetings/status", to: "meetings#status", as: :workspace_meetings_status
    resource :meeting_extension_token, path: "meetings/extension-token", only: %i[create destroy]
    get "search", to: "searches#index", as: :workspace_search
    get "ai-conversation-history", to: "ai_conversation_histories#show", as: :workspace_ai_conversation_history
    get "library", to: "libraries#show", as: :workspace_library
    get "trash", to: "trash#show", as: :workspace_trash
    get "_archive", to: "archive_game#show", as: :workspace_archive_game
    get "_nota_maze", to: "nota_maze_game#show", as: :workspace_nota_maze_game
    get "epistularium", to: "epistularium#show", as: :workspace_epistularium
    get "settings/general", to: "general_settings#show", as: :workspace_general_settings
    patch "settings/general", to: "general_settings#update"
    delete "settings/general", to: "general_settings#destroy"
    post "settings/general/backup", to: "workspace_exports#create", as: :workspace_backup_exports
    get "settings/people", to: "people_settings#show", as: :workspace_people_settings
    patch "settings/people", to: "people_settings#update"
    get "settings/import", to: "import_settings#show", as: :workspace_import_settings
    post "settings/import", to: "import_settings#create"
    get "settings/preferences", to: "preferences#show", as: :workspace_preferences
    patch "settings/preferences", to: "preferences#update"
    get "settings/account", to: "account_settings#show", as: :workspace_account_settings
    patch "settings/account", to: "account_settings#update"
    post "settings/account/delete-request", to: "account_settings#request_deletion", as: :workspace_account_delete_request
    post "settings/account/api-tokens", to: "account_settings#create_api_token", as: :workspace_account_api_tokens
    post "settings/account/api-tokens/:id/revoke", to: "account_settings#revoke_api_token", as: :workspace_account_api_token_revoke
    post "settings/account/api-tokens/:id/rotate", to: "account_settings#rotate_api_token", as: :workspace_account_api_token_rotate
    get "settings/notae-ai", to: "notae_ai_settings#show", as: :workspace_notae_ai_settings
    patch "settings/notae-ai", to: "notae_ai_settings#update"
    get "settings/ai-analytics", to: "ai_analytics_settings#show", as: :workspace_ai_analytics_settings
    patch "settings/ai-analytics", to: "ai_analytics_settings#update"
    get "settings/favicon-lab", to: "favicon_settings#show", as: :workspace_favicon_settings
    get "settings/emoji", to: "emoji_settings#show", as: :workspace_emoji_settings
    post "settings/emoji", to: "emoji_settings#create"
    delete "settings/emoji/:id", to: "emoji_settings#destroy", as: :workspace_emoji_setting
    get "settings/connections", to: "connection_settings#show", as: :workspace_connection_settings
    patch "settings/connections", to: "connection_settings#update"
    get "settings/notifications", to: "notification_settings#show", as: :workspace_notification_settings
    patch "settings/notifications", to: "notification_settings#update"
    post "settings/notifications/test-push", to: "notification_settings#send_test_push", as: :workspace_notification_settings_test_push
    get "settings/operations", to: "operations_settings#show", as: :workspace_operations_settings
    get "settings/subscription", to: "subscription_settings#show", as: :workspace_subscription_settings
    get "settings/kalendarium", to: "kalendarium_settings#show", as: :workspace_kalendarium_settings
    patch "settings/kalendarium", to: "kalendarium_settings#update"
    get "settings/epistularium", to: "epistularium_settings#show", as: :workspace_epistularium_settings
    get "notifications", to: "notifications#index", as: :workspace_notifications
    get "notification-bar", to: "workspace_notification_bars#show", as: :workspace_notification_bar
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
    post "epistularium/accounts", to: "epistularium_accounts#create", as: :epistularium_accounts
    patch "epistularium/accounts/:id", to: "epistularium_accounts#update", as: :epistularium_account
    delete "epistularium/accounts/:id", to: "epistularium_accounts#destroy"
    post "epistularium/accounts/:id/sync", to: "epistularium_accounts#sync", as: :sync_epistularium_account
    get "epistularium/accounts/google/authorize", to: "epistularium_accounts#google_authorize", as: :google_authorize_epistularium_accounts
    get "epistularium/messages/:id", to: "epistularium_messages#show", as: :workspace_epistularium_message
    post "epistularium/messages/:id/suggest", to: "epistularium_messages#suggest", as: :suggest_workspace_epistularium_message
    resources :kalendarium_write_proposals, path: "kalendarium/write_proposals", only: %i[create] do
      member do
        post :confirm
        post :reject
      end
    end
    resources :knowledge_suggestions, only: [] do
      member do
        post :dismiss
        post :convert_to_task
        post :convert_to_nota
        post :refresh
      end
    end
    resources :agent_actions, path: "agent-actions", only: %i[index show new create update] do
      member do
        post :approve
        post :reverse
        post :request_changes
        post :reject
      end
    end
    resources :workflow_runs, path: "workflows", only: %i[index show new create]
    resources :memberships, only: :update
    resources :databases, only: %i[show create update destroy] do
      member do
        post :duplicate
        post :taskify
        post :save_as_template
        post :apply_template
        post :kanbanize
        get :export_gantt_pdf
        get :export_graph_pdf
        get :gantt_embed
        get :graph_embed
        patch :archive
        patch :restore
        patch :permissions
        get :export_csv
        get "panels/:panel", action: :panel, as: :panel
      end
      resource :favorite, only: %i[create destroy], controller: "database_favorites"
      resources :database_views, only: %i[create update]
      patch "database_views/:id/default", to: "database_views#set_default", as: :default_database_view
      resources :db_properties, only: %i[create update destroy]
      resources :db_rows, only: %i[create update destroy] do
        member do
          patch :move
          post :duplicate
          patch :restore
          patch :gantt_range
          post :schedule_in_kalendarium
          post :confirm_schedule_in_kalendarium
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

    get "document-targets", to: "workspace_document_targets#index", as: :workspace_document_targets
    get "sidebar/sections", to: "workspace_sidebar_sections#show", as: :workspace_sidebar_sections
    get "cover-browser/unsplash", to: "workspace_cover_browser#unsplash", as: :workspace_cover_unsplash

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
        post :import
        patch :archive
        patch :restore
        patch :permissions
        patch :remove_tab
        get :export_markdown, to: "page_exports#markdown"
        get :export_pdf, to: "page_exports#pdf"
        post :export_zip, to: "page_exports#create"
        post :save_as_template, to: "page_templates#create"
        get "panels/:panel", action: :panel, as: :panel
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
          get :content
          get :download
          get :export_markdown
          get :panel
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
    get "backups/:token", to: "workspace_exports#download", as: :workspace_backup_download
    get "join/:token", to: "workspace_join_links#show", as: :workspace_join_link
    get "ai-assistant/panel", to: "ai_assistant#panel", as: :workspace_ai_assistant_panel
    get "ai-assistant/updates", to: "ai_assistant#updates", as: :workspace_ai_assistant_updates
    post "ai-assistant", to: "ai_assistant#create", as: :workspace_ai_assistant
  end

  namespace :api do
    namespace :v1 do
      resources :workspaces, only: :index
      scope "workspaces/:workspace_slug" do
        resources :notifications, only: [] do
          collection do
            post :codex_completion
          end
        end
        resources :pages, only: %i[index show create update] do
          collection do
            post :import_markdown, to: "page_documents#create"
          end
          member do
            get :markdown, to: "page_documents#show"
            post :append_markdown, to: "page_documents#append"
          end
          resources :blocks, only: %i[index show create update]
        end
        resources :agent_actions, only: %i[index show create] do
          member do
            post :approve
            post :reverse
          end
        end
        resources :databases, only: %i[index show create update] do
          resources :rows, only: :destroy, controller: "database_rows" do
            member do
              patch :linked_page
            end
          end
        end
        namespace :kalendarium do
          resources :calendars, only: :index
          resources :events, only: %i[index create]
          resources :write_proposals, only: :create do
            member do
              post :confirm
              post :reject
            end
          end
        end
        namespace :meetings do
          resources :sessions, only: %i[index show create] do
            member do
              get :transcript
              post :ingest_transcript
              post :cancel
            end
          end
        end
        namespace :knowledge do
          resources :suggestions, only: :index
          resources :ingestions, only: :create
        end
      end
    end
  end

  get "invitations/:token", to: "invitations#show", as: :invitation
  post "invitations/:token/accept", to: "invitations#accept", as: :accept_invitation
  get "s/:token", to: "public/pages#show", as: :public_share
  get "g/:token", to: "public/databases#show", as: :public_database_share
  get "kalendarium/google/callback", to: "kalendarium_connections#google_callback", as: :kalendarium_google_callback
  get "epistularium/google/callback", to: "epistularium_accounts#google_callback", as: :epistularium_google_callback

  namespace :internal do
    resources :meeting_bot_runs, only: [] do
      collection do
        post :claim
      end
      member do
        post :heartbeat
        post :upload_complete
        post :transcript_complete
        post :failed
      end
    end
  end

  mount Sidekiq::Web => "/sidekiq" if Rails.env.development?
end
