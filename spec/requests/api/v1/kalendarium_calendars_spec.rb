require "rails_helper"

RSpec.describe "API V1 Kalendarium calendars", type: :request do
  def json_body
    JSON.parse(response.body)
  end

  def auth_headers(token)
    { "Authorization" => "Bearer #{token.token}", "Accept" => "application/json" }
  end

  it "filters down to enabled writable calendars when requested" do
    owner = User.create!(email: "api-kal-calendars-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "API Kal calendars", slug: "api-kal-calendars")
    Membership.create!(workspace: workspace, user: owner, role: :owner)

    writable_calendar = KalendariumCalendar.create!(
      workspace: workspace,
      created_by: owner,
      name: "Writable",
      color_hex: "#2563EB",
      time_zone: "UTC",
      source_kind: "local"
    )
    KalendariumCalendar.create!(
      workspace: workspace,
      created_by: owner,
      name: "Read only",
      color_hex: "#7C3AED",
      time_zone: "UTC",
      source_kind: "local",
      read_only: true
    )
    KalendariumCalendar.create!(
      workspace: workspace,
      created_by: owner,
      name: "Disabled",
      color_hex: "#DC2626",
      time_zone: "UTC",
      source_kind: "local",
      enabled: false
    )

    token = ApiToken.create!(user: owner, name: "Kal calendars API")

    get "/api/v1/workspaces/#{workspace.slug}/kalendarium/calendars",
        params: { writable: true },
        headers: auth_headers(token)

    expect(response).to have_http_status(:ok)
    expect(json_body.fetch("data").map { |row| row.fetch("id") }).to eq([ writable_calendar.id ])
    expect(json_body.fetch("data").first.fetch("writable")).to eq(true)
  end

  it "marks legacy writable iCloud calendars as writable in the API payload" do
    owner = User.create!(email: "api-kal-calendars-icloud@example.com", password: "password123")
    workspace = Workspace.create!(name: "API Kal calendars iCloud", slug: "api-kal-calendars-icloud")
    Membership.create!(workspace: workspace, user: owner, role: :owner)

    connection = KalendariumConnection.create!(
      workspace: workspace,
      owner: owner,
      created_by: owner,
      provider: "icloud_caldav",
      label: "iCloud sync",
      provider_username: "apple-id@example.com",
      provider_password: "abcd-efgh-ijkl-mnop",
      enabled: true,
      status: "connected"
    )

    legacy_calendar = KalendariumCalendar.create!(
      workspace: workspace,
      kalendarium_connection: connection,
      created_by: owner,
      provider: "icloud_caldav",
      remote_id: "/123/calendars/family-and-kids/",
      name: "Family and kids",
      color_hex: "#CC73E1",
      time_zone: "Australia/Melbourne",
      source_kind: "provider",
      read_only: true,
      enabled: true,
      metadata_json: { "subscribed" => false }
    )

    token = ApiToken.create!(user: owner, name: "Kal calendars iCloud API")

    get "/api/v1/workspaces/#{workspace.slug}/kalendarium/calendars",
        params: { writable: true },
        headers: auth_headers(token)

    expect(response).to have_http_status(:ok)
    row = json_body.fetch("data").find { |calendar| calendar.fetch("id") == legacy_calendar.id }

    expect(row).to include(
      "id" => legacy_calendar.id,
      "read_only" => true,
      "writable" => true
    )
  end
end
