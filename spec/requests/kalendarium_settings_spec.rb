require "rails_helper"

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
