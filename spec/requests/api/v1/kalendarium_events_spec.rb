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
end
