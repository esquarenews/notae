require "rails_helper"
require "json"
require "open3"
require "tempfile"

RSpec.describe "PWA", type: :request do
  def create_workspace_for(user:, slug:, name:)
    workspace = Workspace.create!(name: name, slug: slug)
    Membership.create!(workspace: workspace, user: user, role: :owner)
    workspace
  end

  it "includes the manifest link and theme metadata in the application layout" do
    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("rel=\"manifest\"")
    expect(response.body).to include(pwa_manifest_path)
    expect(response.body).to include("/icon-light-v5.svg")
    expect(response.body).to include("/icon-dark-v5.svg")
    expect(response.body).to include("/icon-v5.svg")
    expect(response.body).to include("/apple-touch-icon-v5.png")
    expect(response.body).to include("apple-mobile-web-app-title")
    expect(response.body).to include("theme-color")
    expect(response.body).to include("data-controller=\"pwa\"")
    expect(response.body).to include("data-pwa-web-push-public-key-value=")
    expect(response.body).to include("data-pwa-target=\"pushLiveBanner\"")
    expect(response.body).to include("data-pwa-target=\"pushLiveBannerTitle\"")
    expect(response.body).to include("data-pwa-target=\"pushLiveBannerBody\"")
    expect(response.body).not_to include("data-pwa-unread-notification-count-value=")
  end

  it "keeps hidden PWA shell cards hidden until the controller reveals them" do
    stylesheet = Rails.root.join("app/assets/stylesheets/application.css").read

    expect(stylesheet).to include(".notae-pwa-offline-banner[hidden],")
    expect(stylesheet).to include(".notae-pwa-install-card[hidden],")
    expect(stylesheet).to include(".notae-pwa-push-card[hidden],")
    expect(stylesheet).to include(".notae-pwa-live-banner[hidden],")
    expect(stylesheet).to include(".notae-pwa-network-toast[hidden] {")
    expect(stylesheet).to include("display: none !important;")
  end

  it "explains offline mode as read-only in the shell and fallback page" do
    get root_path

    expect(response.body).to include("Cached screens stay available in read-only mode.")

    get pwa_offline_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Recently opened screens can still load from cache in read-only mode")
  end

  it "serves a production-ready web manifest" do
    get pwa_manifest_path

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/manifest+json")

    manifest = JSON.parse(response.body)
    icons = manifest.fetch("icons")

    expect(manifest).to include(
      "id" => "/app",
      "start_url" => "/app",
      "scope" => "/",
      "display" => "standalone",
      "short_name" => "Notae"
    )
    expect(icons).to include(a_hash_including("src" => "/icon-192-v5.png", "sizes" => "192x192"))
    expect(icons).to include(a_hash_including("src" => "/icon-512-v5.png", "sizes" => "512x512"))
    expect(icons).to include(a_hash_including("src" => "/icon-maskable-512-v5.png", "purpose" => "maskable"))
  end

  it "serves a parseable service worker with the offline fallback, private cache clearing, and push hooks" do
    get pwa_service_worker_path

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/javascript")
    expect(response.headers["Service-Worker-Allowed"]).to eq("/")
    expect(response.body).to include("OFFLINE_FALLBACK_URL")
    expect(response.body).to include("CLEAR_PRIVATE_CACHES")
    expect(response.body).to include("/app")
    expect(response.body).to include("/app/notifications/__NOTIFICATION_ID__")
    expect(response.body).to match(/const CACHE_VERSION = "pwa-[0-9a-f]{12}"/)
    expect(response.body).not_to include('const CACHE_VERSION = "pwa-v6"')
    expect(response.body).to include("const ACTIVE_CACHES = [SHELL_CACHE, ASSET_CACHE, FONT_CACHE]")
    expect(response.body).not_to include("const DOCUMENT_CACHE")
    expect(response.body).not_to include("cacheableDocumentResponse")
    expect(response.body).to include("if (!cacheableRequestUrl(url)) return")
    expect(response.body).to include("function cacheableRequestUrl(url)")
    expect(response.body).to include('return url.protocol === "http:" || url.protocol === "https:"')
    expect(response.body).to include('(url.origin === self.location.origin && /\\.(?:woff2?|ttf|otf)$/i.test(url.pathname))')
    expect(response.body).to include("event.respondWith(networkFirstDocument(request))")
    expect(response.body).to include("async function networkFirstDocument(request)")
    expect(response.body).to include("self.addEventListener(\"push\"")
    expect(response.body).to include("self.addEventListener(\"notificationclick\"")
    expect(response.body).to include("requireInteraction: Boolean(payload.require_interaction)")
    expect(response.body).to include("type: \"notae:push-received\"")
    expect(response.body).to include("client.postMessage")
    expect(response.body).to include("const receiptPayload = pushReceiptPayload(payload, { notificationDisplayed, notificationError })")
    expect(response.body).to include("function pushReceiptPayload(payload, { notificationDisplayed = false, notificationError = \"\" } = {})")
    expect(response.body).to include("notificationType: payload.type || payload.notification_type || null")
    expect(response.body).to include("tag: payload.tag || \"\"")
    expect(response.body).to include("icon: payload.icon || \"/icon-192-v5.png\"")
    expect(response.body).to include("requireInteraction: Boolean(payload.require_interaction)")
    expect(response.body).to include("notificationDisplayed")
    expect(response.body).to include("notificationError")
    expect(response.body).to include("} finally {")
    expect(response.body).not_to include("unreadCount")
    expect(response.body).not_to include("unread_count")

    Tempfile.create([ "notae-pwa-service-worker", ".js" ]) do |file|
      file.write(response.body)
      file.flush

      stdout, status = Open3.capture2e("node", "--check", file.path)
      expect(status.success?).to be(true), <<~MESSAGE
        Expected #{pwa_service_worker_path} to parse cleanly with node --check.
        Output:
        #{stdout}
      MESSAGE
    end
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end

  it "redirects signed-out app launches to sign in" do
    get pwa_launch_path

    expect(response).to redirect_to(new_user_session_path)
  end

  it "routes signed-in notification launches through the server and marks them as read" do
    user = User.create!(email: "pwa-notification-launch@example.com", password: "password123")
    workspace = create_workspace_for(user:, slug: "pwa-notification", name: "PWA Notification")
    conversation = AiConversation.create!(
      workspace: workspace,
      user: user,
      scope: Search::AssistantQueryService::SCOPE_WORKSPACE,
      status: AiConversation::STATUS_SUGGESTION,
      prompt: "Proactive workspace suggestion",
      answer: "A new AI suggestion is waiting. [1]"
    )
    suggestion = KnowledgeSuggestion.create!(
      workspace: workspace,
      user: user,
      ai_conversation: conversation,
      kind: KnowledgeSuggestion::KIND_PROACTIVE,
      status: KnowledgeSuggestion::STATUS_ACTIVE,
      title: "Follow up on the board",
      summary: "A new AI suggestion is waiting. [1]",
      insights_json: [],
      task_suggestions_json: [],
      related_notes_json: [],
      sources_json: [],
      generated_at: Time.current,
      expires_at: 6.hours.from_now
    )
    notification = Notification.create!(
      workspace: workspace,
      actor: user,
      recipient: user,
      notifiable: suggestion,
      notification_type: Notification::TYPE_KNOWLEDGE_SUGGESTION_READY,
      metadata: {}
    )
    sign_in user

    get pwa_notification_launch_path(id: notification.id)

    expect(response).to redirect_to(workspace_ai_conversation_history_path(workspace_slug: workspace.slug, conversation_id: conversation.id, anchor: "ai-conversation-#{conversation.id}"))
    expect(notification.reload.read_at).to be_present
  end

  it "falls back to the app launch route when the notification no longer exists" do
    user = User.create!(email: "pwa-notification-missing@example.com", password: "password123")
    create_workspace_for(user:, slug: "pwa-notification-missing", name: "PWA Notification Missing")
    sign_in user

    get pwa_notification_launch_path(id: SecureRandom.uuid)

    expect(response).to redirect_to(pwa_launch_path)
  end

  it "launches signed-in users into the remembered workspace home" do
    user = User.create!(email: "pwa-launch-remembered@example.com", password: "password123")
    primary_workspace = create_workspace_for(user: user, slug: "pwa-primary", name: "PWA Primary")
    remembered_workspace = create_workspace_for(user: user, slug: "pwa-remembered", name: "PWA Remembered")
    sign_in user

    get workspace_path(remembered_workspace.slug)
    get pwa_launch_path

    expect(response).to redirect_to(workspace_path(remembered_workspace.slug))
    expect(primary_workspace.slug).not_to eq(remembered_workspace.slug)
  end

  it "falls back to the first accessible workspace home when no remembered workspace exists" do
    user = User.create!(email: "pwa-launch-first@example.com", password: "password123")
    first_workspace = create_workspace_for(user: user, slug: "pwa-first", name: "PWA First")
    create_workspace_for(user: user, slug: "pwa-second", name: "PWA Second")
    sign_in user

    get pwa_launch_path

    expect(response).to redirect_to(workspace_path(first_workspace.slug))
  end

  it "redirects to new workspace when the signed-in user has no accessible workspaces" do
    user = User.create!(email: "pwa-launch-empty@example.com", password: "password123")
    sign_in user

    get pwa_launch_path

    expect(response).to redirect_to(new_workspace_path)
  end
end
