require "rails_helper"

RSpec.describe "API V1 notifications", type: :request do
  def json_body
    JSON.parse(response.body)
  end

  def auth_headers(token)
    { "Authorization" => "Bearer #{token.token}", "Accept" => "application/json" }
  end

  it "creates a codex completion notification for the authenticated user" do
    user = User.create!(email: "api-notifications@example.com", password: "password123")
    workspace = Workspace.create!(name: "API Notifications", slug: "api-notifications")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    token = ApiToken.create!(user: user, name: "Notifications API", scopes_json: [ ApiToken::SCOPE_NOTIFICATIONS_WRITE ])

    post "/api/v1/workspaces/#{workspace.slug}/notifications/codex_completion",
         params: {
           notification: {
             title: "Codex request completed",
             body: "UI pass is ready for review.",
             path: "/w/#{workspace.slug}/library"
           }
         }.to_json,
         headers: auth_headers(token).merge("Content-Type" => "application/json")

    expect(response).to have_http_status(:created)
    payload = json_body.fetch("data")
    notification = Notification.find(payload.dig("notification", "id"))

    expect(notification.notification_type).to eq(Notification::TYPE_CODEX_REQUEST_COMPLETED)
    expect(notification.workspace_id).to eq(workspace.id)
    expect(notification.recipient_id).to eq(user.id)
    expect(notification.actor_id).to eq(user.id)
    expect(notification.metadata).to include(
      "title" => "codex: request completed",
      "body" => "UI pass is ready for review.",
      "path" => "/w/#{workspace.slug}/library"
    )
    expect(payload.fetch("url")).to eq("/app/notifications/#{notification.id}")

    audit_event = ApiTokenAuditEvent.order(:created_at).last
    expect(audit_event).to have_attributes(
      api_token_id: token.id,
      workspace_id: workspace.id,
      event_type: "allowed",
      request_method: "POST",
      action_name: "codex_completion",
      http_status: 201
    )
    expect(audit_event.required_scopes_json).to eq([ ApiToken::SCOPE_NOTIFICATIONS_WRITE ])
  end

  it "prefixes custom codex titles once" do
    user = User.create!(email: "api-notifications-custom-title@example.com", password: "password123")
    workspace = Workspace.create!(name: "API Notifications custom title", slug: "api-notifications-custom-title")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    token = ApiToken.create!(user: user, name: "Notifications custom title API", scopes_json: [ ApiToken::SCOPE_NOTIFICATIONS_WRITE ])

    post "/api/v1/workspaces/#{workspace.slug}/notifications/codex_completion",
         params: {
           notification: {
             title: "Grid cleanup ready"
           }
         }.to_json,
         headers: auth_headers(token).merge("Content-Type" => "application/json")

    expect(response).to have_http_status(:created)
    notification = Notification.find(json_body.dig("data", "notification", "id"))
    expect(notification.metadata["title"]).to eq("codex: Grid cleanup ready")

    post "/api/v1/workspaces/#{workspace.slug}/notifications/codex_completion",
         params: {
           notification: {
             title: "codex: Grid cleanup ready"
           }
         }.to_json,
         headers: auth_headers(token).merge("Content-Type" => "application/json")

    expect(response).to have_http_status(:created)
    second_notification = Notification.find(json_body.dig("data", "notification", "id"))
    expect(second_notification.metadata["title"]).to eq("codex: Grid cleanup ready")
  end

  it "falls back to the workspace home when given a non-internal destination" do
    user = User.create!(email: "api-notifications-fallback@example.com", password: "password123")
    workspace = Workspace.create!(name: "API Notifications fallback", slug: "api-notifications-fallback")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    token = ApiToken.create!(user: user, name: "Notifications fallback API")

    post "/api/v1/workspaces/#{workspace.slug}/notifications/codex_completion",
         params: {
           notification: {
             title: "Codex request completed",
             path: "https://example.com/not-allowed"
           }
         }.to_json,
         headers: auth_headers(token).merge("Content-Type" => "application/json")

    expect(response).to have_http_status(:created)
    notification = Notification.find(json_body.dig("data", "notification", "id"))

    expect(notification.metadata["path"]).to eq("/w/#{workspace.slug}")
  end

  it "falls back to the workspace home when given a local filesystem destination" do
    user = User.create!(email: "api-notifications-filesystem-fallback@example.com", password: "password123")
    workspace = Workspace.create!(name: "API Notifications filesystem fallback", slug: "api-notifications-filesystem-fallback")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    token = ApiToken.create!(user: user, name: "Notifications filesystem fallback API")

    post "/api/v1/workspaces/#{workspace.slug}/notifications/codex_completion",
         params: {
           notification: {
             title: "Codex request completed",
             path: "/Users/errolschmidt/Documents/tabulae"
           }
         }.to_json,
         headers: auth_headers(token).merge("Content-Type" => "application/json")

    expect(response).to have_http_status(:created)
    notification = Notification.find(json_body.dig("data", "notification", "id"))

    expect(notification.metadata["path"]).to eq("/w/#{workspace.slug}")
    expect(json_body.dig("data", "notification", "path")).to eq("/w/#{workspace.slug}")
  end

  it "falls back to the workspace home when given an unroutable internal-looking destination" do
    user = User.create!(email: "api-notifications-unroutable-fallback@example.com", password: "password123")
    workspace = Workspace.create!(name: "API Notifications unroutable fallback", slug: "api-notifications-unroutable-fallback")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    token = ApiToken.create!(user: user, name: "Notifications unroutable fallback API")

    post "/api/v1/workspaces/#{workspace.slug}/notifications/codex_completion",
         params: {
           notification: {
             title: "Codex request completed",
             path: "/definitely-not-a-notae-route"
           }
         }.to_json,
         headers: auth_headers(token).merge("Content-Type" => "application/json")

    expect(response).to have_http_status(:created)
    notification = Notification.find(json_body.dig("data", "notification", "id"))

    expect(notification.metadata["path"]).to eq("/w/#{workspace.slug}")
  end

  it "records a denied scope audit event when the token lacks notification write access" do
    user = User.create!(email: "api-notifications-denied@example.com", password: "password123")
    workspace = Workspace.create!(name: "API Notifications denied", slug: "api-notifications-denied")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    token = ApiToken.create!(user: user, name: "Read-only token", scopes_json: [ ApiToken::SCOPE_WORKSPACES_READ ])

    post "/api/v1/workspaces/#{workspace.slug}/notifications/codex_completion",
         params: { notification: { title: "Denied" } }.to_json,
         headers: auth_headers(token).merge("Content-Type" => "application/json")

    expect(response).to have_http_status(:forbidden)
    expect(json_body.dig("error", "code")).to eq("insufficient_scope")

    audit_event = ApiTokenAuditEvent.order(:created_at).last
    expect(audit_event).to have_attributes(
      api_token_id: token.id,
      workspace_id: workspace.id,
      event_type: "scope_denied",
      request_method: "POST",
      http_status: 403
    )
    expect(audit_event.required_scopes_json).to eq([ ApiToken::SCOPE_NOTIFICATIONS_WRITE ])
  end
end
