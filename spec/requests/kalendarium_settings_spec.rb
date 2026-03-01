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

  it "creates workspace-shared connections from settings form values" do
    user, workspace = build_stack(suffix: "connections")
    sign_in user
    allow(Kalendarium::SyncConnectionJob).to receive(:perform_later)

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
    expect(Kalendarium::SyncConnectionJob).to have_received(:perform_later).with(connection.id)
  end
end
