require "rails_helper"

RSpec.describe "API V1 Kalendarium events", type: :request do
  def json_body
    JSON.parse(response.body)
  end

  def auth_headers(token)
    { "Authorization" => "Bearer #{token.token}", "Accept" => "application/json" }
  end

  it "requires a valid bearer token" do
    user = User.create!(email: "api-kal-events-auth@example.com", password: "password123")
    workspace = Workspace.create!(name: "API Kal events auth", slug: "api-kal-events-auth")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    get "/api/v1/workspaces/#{workspace.slug}/kalendarium/events"

    expect(response).to have_http_status(:unauthorized)
    expect(json_body.dig("error", "code")).to eq("unauthorized")
  end

  it "returns policy-scoped events filtered by range and calendar ids" do
    owner = User.create!(email: "api-kal-events-owner@example.com", password: "password123")
    outsider = User.create!(email: "api-kal-events-outsider@example.com", password: "password123")
    workspace = Workspace.create!(name: "API Kal events", slug: "api-kal-events")
    other_workspace = Workspace.create!(name: "API Kal events other", slug: "api-kal-events-other")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: other_workspace, user: outsider, role: :owner)

    calendar = KalendariumCalendar.create!(
      workspace: workspace,
      created_by: owner,
      name: "Primary",
      color_hex: "#3B82F6",
      time_zone: "UTC",
      source_kind: "local"
    )
    other_calendar = KalendariumCalendar.create!(
      workspace: workspace,
      created_by: owner,
      name: "Secondary",
      color_hex: "#8B5CF6",
      time_zone: "UTC",
      source_kind: "local"
    )
    KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      title: "In range",
      starts_at_utc: Time.zone.parse("2026-03-01 10:00:00"),
      ends_at_utc: Time.zone.parse("2026-03-01 11:00:00"),
      created_by: owner,
      updated_by: owner,
      reminder_offsets_minutes: [ 10 ]
    )
    KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: other_calendar,
      title: "Wrong calendar",
      starts_at_utc: Time.zone.parse("2026-03-01 12:00:00"),
      ends_at_utc: Time.zone.parse("2026-03-01 13:00:00"),
      created_by: owner,
      updated_by: owner,
      reminder_offsets_minutes: [ 10 ]
    )
    external_calendar = KalendariumCalendar.create!(
      workspace: other_workspace,
      created_by: outsider,
      name: "External",
      color_hex: "#EF4444",
      time_zone: "UTC",
      source_kind: "local"
    )
    KalendariumEvent.create!(
      workspace: other_workspace,
      kalendarium_calendar: external_calendar,
      title: "Outside workspace",
      starts_at_utc: Time.zone.parse("2026-03-01 10:00:00"),
      ends_at_utc: Time.zone.parse("2026-03-01 11:00:00"),
      created_by: outsider,
      updated_by: outsider,
      reminder_offsets_minutes: [ 10 ]
    )

    token = ApiToken.create!(user: owner, name: "Kal events API")
    get "/api/v1/workspaces/#{workspace.slug}/kalendarium/events",
        params: {
          from: "2026-03-01T00:00:00Z",
          to: "2026-03-02T00:00:00Z",
          calendar_ids: [ calendar.id ]
        },
        headers: auth_headers(token)

    expect(response).to have_http_status(:ok)
    titles = json_body.fetch("data").map { |row| row.fetch("title") }
    expect(titles).to eq([ "In range" ])
  end

  it "creates a calendar event on a writable calendar" do
    owner = User.create!(email: "api-kal-events-create@example.com", password: "password123")
    workspace = Workspace.create!(name: "API Kal events create", slug: "api-kal-events-create")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    calendar = KalendariumCalendar.create!(
      workspace: workspace,
      created_by: owner,
      name: "Primary",
      color_hex: "#3B82F6",
      time_zone: "Australia/Melbourne",
      source_kind: "local"
    )
    token = ApiToken.create!(user: owner, name: "Kal create API")

    post "/api/v1/workspaces/#{workspace.slug}/kalendarium/events",
         params: {
           kalendarium_event: {
             kalendarium_calendar_id: calendar.id,
             title: "Board review",
             description: "Review the Q2 board pack",
             location: "Melbourne HQ",
             starts_at: "2026-04-20T10:30:00+10:00",
             ends_at: "2026-04-20T11:30:00+10:00",
             reminder_offsets_minutes: [ 10, 30 ]
           }
         }.to_json,
         headers: auth_headers(token).merge("Content-Type" => "application/json")

    expect(response).to have_http_status(:created)
    payload = json_body.fetch("data")
    event_payload = payload.fetch("event")
    event = KalendariumEvent.find(event_payload.fetch("id"))

    expect(event.title).to eq("Board review")
    expect(event.description).to eq("Review the Q2 board pack")
    expect(event.location).to eq("Melbourne HQ")
    expect(event.reminder_offsets_minutes).to eq([ 10, 30 ])
    expect(event.starts_at_utc.iso8601).to eq("2026-04-20T00:30:00Z")
    expect(event.ends_at_utc.iso8601).to eq("2026-04-20T01:30:00Z")
    expect(payload.fetch("url")).to include("/w/#{workspace.slug}/kalendarium")
  end

  it "syncs provider-backed calendar events without namespace resolution errors" do
    owner = User.create!(email: "api-kal-events-provider-sync@example.com", password: "password123")
    workspace = Workspace.create!(name: "API Kal events provider sync", slug: "api-kal-events-provider-sync")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    connection = KalendariumConnection.create!(
      workspace: workspace,
      owner: owner,
      created_by: owner,
      provider: "google",
      label: "Google Calendar",
      provider_username: "owner@example.com",
      refresh_token: "refresh-token",
      enabled: true,
      status: "connected"
    )
    calendar = KalendariumCalendar.create!(
      workspace: workspace,
      kalendarium_connection: connection,
      created_by: owner,
      provider: "google",
      remote_id: "primary",
      name: "Primary",
      color_hex: "#3B82F6",
      time_zone: "Australia/Melbourne",
      source_kind: "provider",
      read_only: false
    )
    token = ApiToken.create!(user: owner, name: "Kal provider sync API")
    sync_service = instance_double(::Kalendarium::ProviderEventSyncService, upsert_remote!: true)
    allow(::Kalendarium::ProviderEventSyncService).to receive(:new).and_return(sync_service)

    post "/api/v1/workspaces/#{workspace.slug}/kalendarium/events",
         params: {
           kalendarium_event: {
             kalendarium_calendar_id: calendar.id,
             title: "Synced provider event",
             starts_at: "2026-04-20T10:30:00+10:00",
             ends_at: "2026-04-20T11:30:00+10:00"
           }
         }.to_json,
         headers: auth_headers(token).merge("Content-Type" => "application/json")

    expect(response).to have_http_status(:created)
    expect(sync_service).to have_received(:upsert_remote!)
    expect(json_body.dig("data", "warning")).to be_nil
  end

  it "normalizes all-day events using the supplied time zone" do
    owner = User.create!(email: "api-kal-events-all-day@example.com", password: "password123")
    workspace = Workspace.create!(name: "API Kal events all day", slug: "api-kal-events-all-day")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    calendar = KalendariumCalendar.create!(
      workspace: workspace,
      created_by: owner,
      name: "Primary",
      color_hex: "#3B82F6",
      time_zone: "UTC",
      source_kind: "local"
    )
    token = ApiToken.create!(user: owner, name: "Kal all-day API")

    post "/api/v1/workspaces/#{workspace.slug}/kalendarium/events",
         params: {
           kalendarium_event: {
             kalendarium_calendar_id: calendar.id,
             title: "Offsite",
             starts_at: "2026-04-20",
             ends_at: "2026-04-20",
             time_zone: "Australia/Melbourne",
             all_day: true
           }
         }.to_json,
         headers: auth_headers(token).merge("Content-Type" => "application/json")

    expect(response).to have_http_status(:created)
    event = KalendariumEvent.find(json_body.dig("data", "event", "id"))

    expect(event.all_day).to be(true)
    expect(event.starts_at_utc.iso8601).to eq("2026-04-19T14:00:00Z")
    expect(event.ends_at_utc.iso8601).to eq("2026-04-20T13:59:59Z")
  end

  it "rejects event creation on a read-only calendar" do
    owner = User.create!(email: "api-kal-events-read-only@example.com", password: "password123")
    workspace = Workspace.create!(name: "API Kal events read only", slug: "api-kal-events-read-only")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    calendar = KalendariumCalendar.create!(
      workspace: workspace,
      created_by: owner,
      name: "Read only",
      color_hex: "#3B82F6",
      time_zone: "UTC",
      source_kind: "local",
      read_only: true
    )
    token = ApiToken.create!(user: owner, name: "Kal read-only API")

    post "/api/v1/workspaces/#{workspace.slug}/kalendarium/events",
         params: {
           kalendarium_event: {
             kalendarium_calendar_id: calendar.id,
             title: "Should fail",
             starts_at: "2026-04-20T10:30:00Z",
             ends_at: "2026-04-20T11:30:00Z"
           }
         }.to_json,
         headers: auth_headers(token).merge("Content-Type" => "application/json")

    expect(response).to have_http_status(:forbidden)
    expect(json_body.dig("error", "code")).to eq("forbidden")
  end

  it "allows event creation on a legacy writable iCloud calendar" do
    owner = User.create!(email: "api-kal-events-legacy-icloud@example.com", password: "password123")
    workspace = Workspace.create!(name: "API Kal events legacy iCloud", slug: "api-kal-events-legacy-icloud")
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
    calendar = KalendariumCalendar.create!(
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
    token = ApiToken.create!(user: owner, name: "Kal legacy iCloud API")

    post "/api/v1/workspaces/#{workspace.slug}/kalendarium/events",
         params: {
           kalendarium_event: {
             kalendarium_calendar_id: calendar.id,
             title: "Family review",
             starts_at: "2026-04-20T10:30:00+10:00",
             ends_at: "2026-04-20T11:30:00+10:00"
           }
         }.to_json,
         headers: auth_headers(token).merge("Content-Type" => "application/json")

    expect(response).to have_http_status(:created)
    expect(KalendariumEvent.order(:created_at).last.kalendarium_calendar_id).to eq(calendar.id)
  end
end
