require "rails_helper"
require "cgi"

RSpec.describe "Kalendarium settings", type: :request do
  include ActiveJob::TestHelper

  before do
    clear_enqueued_jobs
  end

  def build_stack(suffix:)
    user = User.create!(email: "kal-settings-#{suffix}@example.com", password: "password123")
    workspace = Workspace.create!(name: "Kal Settings #{suffix}", slug: "kal-settings-#{suffix}")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    [ user, workspace ]
  end

  it "renders settings and saves extra timezone rails for the user" do
    user, workspace = build_stack(suffix: "timezones")
    sign_in user

    get workspace_kalendarium_settings_path(workspace_slug: workspace.slug)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Kalendārium display")
    expect(response.body).to match(/class="notae-content notae-content-scroll[^"]*"/)
    expect(response.body).not_to include("notae-content-wide")
    expect(response.body).to include("<section class=\"notae-settings-shell\"")

    patch workspace_kalendarium_settings_path(workspace_slug: workspace.slug), params: {
      user: {
        calendar_extra_time_zones: [ "UTC", "America/New_York", "" ]
      }
    }

    expect(response).to redirect_to(workspace_kalendarium_settings_path(workspace_slug: workspace.slug))
    expect(user.reload.calendar_extra_time_zone_list).to eq([ "UTC", "America/New_York" ])
  end

  it "returns a local turbo stream flash for calendar row updates" do
    user, workspace = build_stack(suffix: "calendar-row-turbo")
    calendar = KalendariumCalendar.create!(
      workspace: workspace,
      created_by: user,
      name: "Family",
      color_hex: "#336699",
      time_zone: "UTC",
      enabled: true
    )
    sign_in user

    patch kalendarium_calendar_path(workspace_slug: workspace.slug, id: calendar.id),
          params: { kalendarium_calendar: { enabled: "0", time_zone: "Australia/Melbourne" } },
          headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include('turbo-stream action="replace" target="settings_flash_messages"')
    expect(response.body).to include("Calendar updated.")
    expect(calendar.reload.enabled).to be(false)
    expect(calendar.time_zone).to eq("Australia/Melbourne")
  end

  it "renders Google connections as OAuth-only in settings UI" do
    user, workspace = build_stack(suffix: "oauth-only-ui")
    connection = KalendariumConnection.create!(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "google",
      label: "Google calendar",
      access_token: "token",
      refresh_token: "refresh-token",
      enabled: true,
      status: "connected"
    )
    KalendariumCalendar.create!(
      workspace: workspace,
      kalendarium_connection: connection,
      created_by: user,
      provider: "google",
      source_kind: "provider",
      name: "Primary",
      color_hex: "#336699",
      time_zone: "UTC",
      enabled: true
    )
    sign_in user

    get workspace_kalendarium_settings_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Connect Google with OAuth")
    expect(response.body).to include("Use a different connection label for each Google account")
    expect(response.body).to include("value=\"Google calendar 2\"")
    expect(response.body).to include("action=\"/w/#{workspace.slug}/kalendarium/connections/google_authorize\"")
    expect(response.body).to include("data-controller=\"google-oauth-launch\"")
    expect(response.body).to include("submit-&gt;google-oauth-launch#submit")
    expect(response.body).to include("data-google-oauth-launch=\"true\"")
    expect(response.body).to include("Google OAuth is not configured on the server.")
    expect(response.body).not_to include("Connect Google with OAuth</button>")
    expect(response.body).not_to include("Access token (Google)")
    expect(response.body).not_to include("Refresh token (Google)")
    expect(response.body).not_to include(">Google</option>")
    expect(response.body).to include("Turn off <strong>Show in Kalendārium</strong>")
    expect(response.body).to include("Google connection · 1 calendar")
    expect(response.body).to include("Show in Kalendārium")
    expect(response.headers["Content-Security-Policy"]).to include("form-action 'self'")
    expect(response.headers["Content-Security-Policy"]).to include("https://accounts.google.com")
  end

  it "creates workspace-shared connections from settings form values and syncs immediately" do
    user, workspace = build_stack(suffix: "connections")
    sign_in user
    sync_service = instance_double(Kalendarium::ConnectionSyncService, call: true)
    allow(Kalendarium::ConnectionSyncService).to receive(:new).and_return(sync_service)

    post kalendarium_connections_path(workspace_slug: workspace.slug), params: {
      kalendarium_connection: {
        owner_scope: "workspace",
        provider: "ics",
        label: "Team ICS",
        ics_url: "https://example.com/team.ics",
        enabled: "1"
      },
      sync_now: "1"
    }

    connection = KalendariumConnection.order(:created_at).last
    expect(connection.owner).to eq(workspace)
    expect(connection.provider).to eq("ics")
    expect(connection.ics_url).to eq("https://example.com/team.ics")
    expect(Kalendarium::ConnectionSyncService).to have_received(:new).with(connection: connection)
    expect(sync_service).to have_received(:call)
  end

  it "returns turbo stream updates for connection toggles in settings" do
    user, workspace = build_stack(suffix: "connection-toggle-turbo")
    connection = KalendariumConnection.create!(
      workspace: workspace,
      owner: workspace,
      created_by: user,
      provider: "ics",
      label: "School calendar",
      ics_url: "https://example.com/school.ics",
      enabled: true,
      status: "connected"
    )
    sign_in user

    patch kalendarium_connection_path(workspace_slug: workspace.slug, id: connection.id),
          params: { kalendarium_connection: { enabled: "0" } },
          headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include('turbo-stream action="replace" target="settings_flash_messages"')
    expect(response.body).to include(%(turbo-stream action="replace" target="settings_row_kalendarium_connection_#{connection.id}"))
    expect(response.body).to include("Connection updated.")
    expect(connection.reload.enabled).to be(false)
  end


  it "rejects copying a shared source connection without source update permission" do
    owner, workspace = build_stack(suffix: "source-copy-owner")
    member = User.create!(email: "kal-source-member-#{SecureRandom.hex(4)}@example.com", password: "password123")
    Membership.create!(workspace: workspace, user: member, role: :member)
    sign_in member

    source_connection = KalendariumConnection.create!(
      workspace: workspace,
      owner: workspace,
      created_by: owner,
      provider: "ics",
      label: "Owner shared feed",
      ics_url: "https://example.com/owner-shared.ics",
      enabled: true,
      status: "connected"
    )

    expect do
      post kalendarium_connections_path(workspace_slug: workspace.slug), params: {
        source_connection_id: source_connection.id,
        owner_scope: "user",
        workspace_scope: "this_workspace",
        sync_now: "0"
      }
    end.not_to change(KalendariumConnection, :count)

    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to eq("You are not authorized to perform this action.")
  end

  it "creates per-workspace copies when adding a connection from another workspace" do
    user, workspace = build_stack(suffix: "source-copy-target")
    source_workspace = Workspace.create!(name: "Kal Settings source-copy", slug: "kal-settings-source-copy")
    Membership.create!(workspace: source_workspace, user: user, role: :owner)
    sign_in user

    source_connection = KalendariumConnection.create!(
      workspace: source_workspace,
      owner: source_workspace,
      created_by: user,
      provider: "ics",
      label: "Shared feed",
      ics_url: "https://example.com/shared.ics",
      enabled: true,
      status: "connected",
      settings_json: { "workspace_scope" => "this_workspace" }
    )
    sync_service = instance_double(Kalendarium::ConnectionSyncService, call: true)
    allow(Kalendarium::ConnectionSyncService).to receive(:new).and_return(sync_service)

    post kalendarium_connections_path(workspace_slug: workspace.slug), params: {
      source_connection_id: source_connection.id,
      owner_scope: "workspace",
      workspace_scope: "this_workspace",
      sync_now: "1"
    }

    copied_connection = KalendariumConnection.find_by!(
      workspace: workspace,
      owner: workspace,
      provider: "ics",
      label: "Shared feed"
    )
    expect(copied_connection.id).not_to eq(source_connection.id)
    expect(copied_connection.ics_url).to eq("https://example.com/shared.ics")
    expect(copied_connection.settings_json["source_connection_id"]).to eq(source_connection.id)
    expect(Kalendarium::ConnectionSyncService).to have_received(:new).with(connection: copied_connection)
  end

  it "stores all-workspaces visibility on one connection instead of creating workspace copies" do
    user, workspace = build_stack(suffix: "all-workspaces-target")
    second_workspace = Workspace.create!(name: "Kal Settings all-workspaces-second", slug: "kal-settings-all-workspaces-second")
    Membership.create!(workspace: second_workspace, user: user, role: :owner)
    sign_in user

    post kalendarium_connections_path(workspace_slug: workspace.slug), params: {
      kalendarium_connection: {
        owner_scope: "workspace",
        provider: "ics",
        label: "All workspaces feed",
        ics_url: "https://example.com/all-workspaces.ics",
        enabled: "1"
      },
      workspace_scope: "all_workspaces",
      sync_now: "0"
    }

    connection = KalendariumConnection.find_by!(
      workspace: workspace,
      owner: workspace,
      provider: "ics",
      label: "All workspaces feed"
    )
    expect(connection.settings_json["workspace_scope"]).to eq("all_workspaces")
    expect(KalendariumConnection.where(provider: "ics", label: "All workspaces feed").count).to eq(1)

    get workspace_kalendarium_settings_path(workspace_slug: second_workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("All workspaces feed")
    expect(response.body).to include("Visible in:")
    expect(response.body).to include("All workspaces")
  end

  it "deletes a connection from one workspace without affecting another workspace copy" do
    user, workspace = build_stack(suffix: "delete-isolation-target")
    second_workspace = Workspace.create!(name: "Kal Settings delete-isolation-second", slug: "kal-settings-delete-isolation-second")
    Membership.create!(workspace: second_workspace, user: user, role: :owner)
    sign_in user

    target_connection = KalendariumConnection.create!(
      workspace: workspace,
      owner: workspace,
      created_by: user,
      provider: "ics",
      label: "Delete isolation feed",
      ics_url: "https://example.com/delete-isolation.ics",
      enabled: true,
      status: "connected"
    )
    sibling_connection = KalendariumConnection.create!(
      workspace: second_workspace,
      owner: second_workspace,
      created_by: user,
      provider: "ics",
      label: "Delete isolation feed",
      ics_url: "https://example.com/delete-isolation.ics",
      enabled: true,
      status: "connected"
    )

    delete kalendarium_connection_path(workspace_slug: workspace.slug, id: target_connection.id)

    expect(KalendariumConnection.exists?(target_connection.id)).to be(false)
    expect(KalendariumConnection.exists?(sibling_connection.id)).to be(true)
  end

  it "creates an iCloud CalDAV connection with credentials and syncs immediately" do
    user, workspace = build_stack(suffix: "icloud-connect")
    sign_in user
    sync_service = instance_double(Kalendarium::ConnectionSyncService, call: true)
    allow(Kalendarium::ConnectionSyncService).to receive(:new).and_return(sync_service)

    post kalendarium_connections_path(workspace_slug: workspace.slug), params: {
      kalendarium_connection: {
        owner_scope: "user",
        provider: "icloud_caldav",
        label: "My iCloud",
        provider_username: "apple@example.com",
        provider_password: "app-specific-password",
        enabled: "1"
      },
      sync_now: "1"
    }

    connection = KalendariumConnection.order(:created_at).last
    expect(connection.owner).to eq(user)
    expect(connection.provider).to eq("icloud_caldav")
    expect(connection.provider_username).to eq("apple@example.com")
    expect(connection.provider_password).to eq("app-specific-password")
    expect(Kalendarium::ConnectionSyncService).to have_received(:new).with(connection: connection)
    expect(sync_service).to have_received(:call)
  end

  it "creates a Google connection with tokens and syncs immediately" do
    user, workspace = build_stack(suffix: "google-connect")
    sign_in user
    sync_service = instance_double(Kalendarium::ConnectionSyncService, call: true)
    allow(Kalendarium::ConnectionSyncService).to receive(:new).and_return(sync_service)

    post kalendarium_connections_path(workspace_slug: workspace.slug), params: {
      kalendarium_connection: {
        owner_scope: "workspace",
        provider: "google",
        label: "Google calendar",
        access_token: "google-access-token",
        refresh_token: "google-refresh-token",
        enabled: "1"
      },
      sync_now: "1"
    }

    connection = KalendariumConnection.order(:created_at).last
    expect(connection.owner).to eq(workspace)
    expect(connection.provider).to eq("google")
    expect(connection.access_token).to eq("google-access-token")
    expect(connection.refresh_token).to eq("google-refresh-token")
    expect(Kalendarium::ConnectionSyncService).to have_received(:new).with(connection: connection)
    expect(sync_service).to have_received(:call)
  end

  it "redirects directly to Google OAuth with a signed state payload" do
    user, workspace = build_stack(suffix: "google-oauth-authorize")
    sign_in user
    oauth_service = instance_double(Kalendarium::GoogleOauthService)
    allow(Kalendarium::GoogleOauthService).to receive(:new).and_return(oauth_service)
    allow(oauth_service).to receive(:authorization_url) do |redirect_uri:, state:|
      payload = Rails.application.message_verifier("kalendarium_google_oauth_state").verify(state)
      expect(payload["workspace_id"]).to eq(workspace.id)
      expect(payload["user_id"]).to eq(user.id)
      expect(payload["owner_scope"]).to eq("workspace")
      expect(payload["label"]).to eq("Team Google")
      expect(redirect_uri).to end_with(kalendarium_google_callback_path)
      "https://accounts.google.com/o/oauth2/v2/auth?state=#{CGI.escape(state)}"
    end

    get google_authorize_kalendarium_connections_path(workspace_slug: workspace.slug), params: {
      owner_scope: "workspace",
      label: "Team Google"
    }

    expect(response).to have_http_status(:found)
    expect(response.headers["Location"]).to include("accounts.google.com/o/oauth2")
  end

  it "uses the configured public app host for Google OAuth when the request arrives via localhost" do
    user, workspace = build_stack(suffix: "google-oauth-public-host")
    sign_in user
    oauth_service = instance_double(Kalendarium::GoogleOauthService)
    allow(Kalendarium::GoogleOauthService).to receive(:new).and_return(oauth_service)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("APP_BASE_URL").and_return(nil)
    allow(ENV).to receive(:[]).with("APP_HOST").and_return("notae.example.com")
    allow(ENV).to receive(:[]).with("APP_PORT").and_return("443")
    allow(ENV).to receive(:[]).with("APP_PROTOCOL").and_return(nil)
    allow(oauth_service).to receive(:authorization_url) do |redirect_uri:, state:|
      payload = Rails.application.message_verifier("kalendarium_google_oauth_state").verify(state)
      expect(payload["workspace_id"]).to eq(workspace.id)
      expect(redirect_uri).to eq("https://notae.example.com#{kalendarium_google_callback_path}")
      "https://accounts.google.com/o/oauth2/v2/auth?state=#{CGI.escape(state)}"
    end

    get google_authorize_kalendarium_connections_path(workspace_slug: workspace.slug), params: {
      owner_scope: "workspace",
      label: "Team Google"
    }, headers: {
      "Host" => "localhost:4000"
    }

    expect(response).to have_http_status(:found)
    expect(response.headers["Location"]).to include("accounts.google.com/o/oauth2")
  end

  it "redirects to Google OAuth for Turbo requests without rendering a handoff page" do
    user, workspace = build_stack(suffix: "google-oauth-turbo")
    sign_in user
    oauth_service = instance_double(Kalendarium::GoogleOauthService)
    allow(Kalendarium::GoogleOauthService).to receive(:new).and_return(oauth_service)
    allow(oauth_service).to receive(:authorization_url).and_return("https://accounts.google.com/o/oauth2/v2/auth?client_id=test")

    get google_authorize_kalendarium_connections_path(workspace_slug: workspace.slug), headers: {
      "Turbo-Visit" => "true",
      "Accept" => "text/vnd.turbo-stream.html, text/html"
    }

    expect(response).to have_http_status(:found)
    expect(response.headers["Location"]).to include("accounts.google.com/o/oauth2")
  end

  it "handles Google OAuth callback by creating connection, storing tokens, and queueing initial sync" do
    user, workspace = build_stack(suffix: "google-oauth-callback")
    sign_in user
    state = Rails.application.message_verifier("kalendarium_google_oauth_state").generate(
      {
        "workspace_id" => workspace.id,
        "user_id" => user.id,
        "owner_scope" => "workspace",
        "label" => "Workspace Google"
      },
      expires_in: 20.minutes
    )
    oauth_service = instance_double(Kalendarium::GoogleOauthService, exchange_code!: {
      access_token: "oauth-access",
      refresh_token: "oauth-refresh",
      scope: "https://www.googleapis.com/auth/calendar",
      token_type: "Bearer",
      expires_in: 3600
    })
    allow(Kalendarium::GoogleOauthService).to receive(:new).and_return(oauth_service)
    allow(Kalendarium::GoogleOauthService).to receive(:resolved_client_id).and_return("oauth-client-id")
    allow(Kalendarium::GoogleOauthService).to receive(:resolved_client_secret).and_return("oauth-client-secret")
    expect do
      get kalendarium_google_callback_path, params: {
        state: state,
        code: "google-auth-code"
      }
    end.to have_enqueued_job(Kalendarium::SyncConnectionJob)

    connection = KalendariumConnection.order(:created_at).last
    expect(connection.owner).to eq(workspace)
    expect(connection.provider).to eq("google")
    expect(connection.label).to eq("Workspace Google")
    expect(connection.access_token).to eq("oauth-access")
    expect(connection.refresh_token).to eq("oauth-refresh")
    expect(connection.oauth_client_id).to eq("oauth-client-id")
    expect(connection.oauth_client_secret).to eq("oauth-client-secret")
    expect(connection.status).to eq("connected")
    expect(connection.enabled).to be(true)
    expect(connection.scopes_json).to include("https://www.googleapis.com/auth/calendar")
    expect(connection.settings_json["google_token_type"]).to eq("Bearer")
    expect(response).to redirect_to(workspace_kalendarium_settings_path(workspace_slug: workspace.slug))
    expect(flash[:notice]).to eq("Google calendar connected. Initial sync queued.")
  end

  it "handles Google OAuth callback by updating an existing Google connection and queueing initial sync" do
    user, workspace = build_stack(suffix: "google-oauth-update")
    sign_in user
    connection = KalendariumConnection.create!(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "google",
      label: "Existing Google",
      access_token: "old-access-token",
      refresh_token: "existing-refresh-token"
    )
    state = Rails.application.message_verifier("kalendarium_google_oauth_state").generate(
      {
        "workspace_id" => workspace.id,
        "user_id" => user.id,
        "connection_id" => connection.id
      },
      expires_in: 20.minutes
    )
    oauth_service = instance_double(Kalendarium::GoogleOauthService, exchange_code!: {
      access_token: "new-access-token",
      refresh_token: nil,
      scope: "https://www.googleapis.com/auth/calendar",
      token_type: "Bearer",
      expires_in: 1800
    })
    allow(Kalendarium::GoogleOauthService).to receive(:new).and_return(oauth_service)
    allow(Kalendarium::GoogleOauthService).to receive(:resolved_client_id).and_return("oauth-client-id")
    allow(Kalendarium::GoogleOauthService).to receive(:resolved_client_secret).and_return("oauth-client-secret")
    expect do
      get kalendarium_google_callback_path, params: {
        state: state,
        code: "google-auth-code"
      }
    end.to have_enqueued_job(Kalendarium::SyncConnectionJob).with(connection.id)

    expect(response).to redirect_to(workspace_kalendarium_settings_path(workspace_slug: workspace.slug))
    connection.reload
    expect(connection.access_token).to eq("new-access-token")
    expect(connection.refresh_token).to eq("existing-refresh-token")
    expect(connection.oauth_client_id).to eq("oauth-client-id")
    expect(connection.oauth_client_secret).to eq("oauth-client-secret")
    expect(connection.status).to eq("connected")
    expect(connection.enabled).to be(true)
    expect(flash[:notice]).to eq("Google calendar connected. Initial sync queued.")
  end

  it "runs immediate sync from the connection sync action" do
    user, workspace = build_stack(suffix: "sync-action-queue")
    sign_in user
    connection = KalendariumConnection.create!(
      workspace: workspace,
      owner: workspace,
      created_by: user,
      provider: "google",
      label: "Sync me",
      access_token: "token",
      refresh_token: "refresh-token",
      enabled: true,
      status: "connected"
    )

    sync_service = instance_double(Kalendarium::ConnectionSyncService, call: true)
    allow(Kalendarium::ConnectionSyncService).to receive(:new).with(connection: connection).and_return(sync_service)

    post sync_kalendarium_connection_path(workspace_slug: workspace.slug, id: connection.id)

    expect(response).to redirect_to(workspace_kalendarium_settings_path(workspace_slug: workspace.slug))
    expect(flash[:notice]).to eq("Sync completed.")
    expect(Kalendarium::ConnectionSyncService).to have_received(:new).with(connection: connection)
    expect(sync_service).to have_received(:call)
  end

  it "uses the bulk destroy service for deleting a calendar connection" do
    user, workspace = build_stack(suffix: "destroy-action-service")
    sign_in user
    connection = KalendariumConnection.create!(
      workspace: workspace,
      owner: workspace,
      created_by: user,
      provider: "google",
      label: "Delete me",
      access_token: "token",
      refresh_token: "refresh-token",
      enabled: true,
      status: "connected"
    )
    destroy_service = instance_double(Kalendarium::ConnectionDestroyService, call: true)
    allow(Kalendarium::ConnectionDestroyService).to receive(:new).with(connection: connection).and_return(destroy_service)

    delete kalendarium_connection_path(workspace_slug: workspace.slug, id: connection.id)

    expect(Kalendarium::ConnectionDestroyService).to have_received(:new).with(connection: connection)
    expect(destroy_service).to have_received(:call)
    expect(response).to redirect_to(workspace_kalendarium_settings_path(workspace_slug: workspace.slug))
    expect(flash[:notice]).to eq("Connection removed.")
  end

  it "rejects iCloud CalDAV connection when username/password are missing" do
    user, workspace = build_stack(suffix: "icloud-invalid")
    sign_in user
    allow(Kalendarium::ConnectionSyncService).to receive(:new)

    post kalendarium_connections_path(workspace_slug: workspace.slug), params: {
      kalendarium_connection: {
        owner_scope: "user",
        provider: "icloud_caldav",
        label: "Broken iCloud",
        provider_username: "",
        provider_password: "",
        enabled: "1"
      },
      sync_now: "1"
    }

    expect(response).to redirect_to(workspace_kalendarium_settings_path(workspace_slug: workspace.slug))
    expect(flash[:alert]).to include("Provider username is required for iCloud CalDAV")
    expect(flash[:alert]).to include("Provider password is required for iCloud CalDAV")
    expect(KalendariumConnection.where(workspace: workspace).count).to eq(0)
    expect(Kalendarium::ConnectionSyncService).not_to have_received(:new)
  end

  it "shows a sync failure immediately when iCloud authentication fails" do
    user, workspace = build_stack(suffix: "icloud-sync-fail")
    sign_in user

    sync_service = instance_double(Kalendarium::ConnectionSyncService)
    allow(Kalendarium::ConnectionSyncService).to receive(:new).and_return(sync_service)
    allow(sync_service).to receive(:call).and_raise(RuntimeError, "CalDAV authentication failed (401). Use Apple ID email and an app-specific password.")

    post kalendarium_connections_path(workspace_slug: workspace.slug), params: {
      kalendarium_connection: {
        owner_scope: "workspace",
        provider: "icloud_caldav",
        label: "iCloud bad auth",
        provider_username: "apple@example.com",
        provider_password: "aaaa-bbbb-cccc-dddd",
        enabled: "1"
      },
      sync_now: "1"
    }

    expect(response).to redirect_to(workspace_kalendarium_settings_path(workspace_slug: workspace.slug))
    expect(flash[:alert]).to include("Connection saved but sync failed:")
    expect(flash[:alert]).to include("CalDAV authentication failed (401)")
  end
end
