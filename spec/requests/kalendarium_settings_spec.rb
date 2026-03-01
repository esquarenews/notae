require "rails_helper"
require "cgi"

RSpec.describe "Kalendarium settings", type: :request do
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

    patch workspace_kalendarium_settings_path(workspace_slug: workspace.slug), params: {
      user: {
        calendar_extra_time_zones: [ "UTC", "America/New_York", "" ]
      }
    }

    expect(response).to redirect_to(workspace_kalendarium_settings_path(workspace_slug: workspace.slug))
    expect(user.reload.calendar_extra_time_zone_list).to eq([ "UTC", "America/New_York" ])
  end

  it "renders Google connections as OAuth-only in settings UI" do
    user, workspace = build_stack(suffix: "oauth-only-ui")
    sign_in user

    get workspace_kalendarium_settings_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Connect Google with OAuth")
    expect(response.body).to include("action=\"/w/#{workspace.slug}/kalendarium/connections/google_authorize\"")
    expect(response.body).to include("data-turbo=\"false\"")
    expect(response.body).to include("data-google-oauth-launch=\"true\"")
    expect(response.body).to include("Google OAuth is not configured on the server.")
    expect(response.body).not_to include("Connect Google with OAuth</button>")
    expect(response.body).not_to include("Access token (Google)")
    expect(response.body).not_to include("Refresh token (Google)")
    expect(response.body).not_to include(">Google</option>")
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

  it "returns a same-origin handoff page for Google OAuth with a signed state payload" do
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

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Redirecting to Google OAuth")
    expect(response.body).to include("accounts.google.com/o/oauth2")
  end

  it "renders a turbo-safe redirect page for Google OAuth requests intercepted by Turbo" do
    user, workspace = build_stack(suffix: "google-oauth-turbo")
    sign_in user
    oauth_service = instance_double(Kalendarium::GoogleOauthService)
    allow(Kalendarium::GoogleOauthService).to receive(:new).and_return(oauth_service)
    allow(oauth_service).to receive(:authorization_url).and_return("https://accounts.google.com/o/oauth2/v2/auth?client_id=test")

    get google_authorize_kalendarium_connections_path(workspace_slug: workspace.slug), headers: {
      "Turbo-Visit" => "true",
      "Accept" => "text/vnd.turbo-stream.html, text/html"
    }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("http-equiv=\"refresh\"")
    expect(response.body).to include("accounts.google.com/o/oauth2")
  end

  it "handles Google OAuth callback by creating connection, storing tokens, and syncing" do
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
      scope: "https://www.googleapis.com/auth/calendar.readonly https://www.googleapis.com/auth/calendar.events.readonly",
      token_type: "Bearer",
      expires_in: 3600
    })
    allow(Kalendarium::GoogleOauthService).to receive(:new).and_return(oauth_service)
    sync_service = instance_double(Kalendarium::ConnectionSyncService, call: true)
    allow(Kalendarium::ConnectionSyncService).to receive(:new).and_return(sync_service)

    get kalendarium_google_callback_path, params: {
      state: state,
      code: "google-auth-code"
    }

    connection = KalendariumConnection.order(:created_at).last
    expect(connection.owner).to eq(workspace)
    expect(connection.provider).to eq("google")
    expect(connection.label).to eq("Workspace Google")
    expect(connection.access_token).to eq("oauth-access")
    expect(connection.refresh_token).to eq("oauth-refresh")
    expect(connection.scopes_json).to include("https://www.googleapis.com/auth/calendar.readonly")
    expect(connection.settings_json["google_token_type"]).to eq("Bearer")
    expect(Kalendarium::ConnectionSyncService).to have_received(:new).with(connection: connection)
    expect(sync_service).to have_received(:call)
    expect(response).to redirect_to(workspace_kalendarium_settings_path(workspace_slug: workspace.slug))
    expect(flash[:notice]).to eq("Google calendar connected and synced.")
  end

  it "handles Google OAuth callback by updating an existing Google connection" do
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
      scope: "https://www.googleapis.com/auth/calendar.readonly",
      token_type: "Bearer",
      expires_in: 1800
    })
    allow(Kalendarium::GoogleOauthService).to receive(:new).and_return(oauth_service)
    sync_service = instance_double(Kalendarium::ConnectionSyncService, call: true)
    allow(Kalendarium::ConnectionSyncService).to receive(:new).and_return(sync_service)

    get kalendarium_google_callback_path, params: {
      state: state,
      code: "google-auth-code"
    }

    expect(response).to redirect_to(workspace_kalendarium_settings_path(workspace_slug: workspace.slug))
    expect(connection.reload.access_token).to eq("new-access-token")
    expect(connection.refresh_token).to eq("existing-refresh-token")
    expect(Kalendarium::ConnectionSyncService).to have_received(:new).with(connection: connection)
    expect(sync_service).to have_received(:call)
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
