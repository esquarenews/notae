require "rails_helper"

RSpec.describe Notae::RecordRequestPerformanceJob, type: :job do
  it "persists a normalized performance sample outside the request" do
    workspace = Workspace.create!(name: "Async performance", slug: "async-performance")
    sample = {
      action: "WorkspaceNotificationBarsController#show",
      path: "/w/#{workspace.slug}/notification-bar",
      total_ms: 920.4,
      sql_queries: 18,
      sql_ms: 340.2,
      status: 200,
      recorded_at: Time.zone.parse("2026-07-11 09:30:00")
    }

    described_class.perform_now(workspace.id, sample)

    expect(Notae::RequestPerformanceStore.fetch(workspace_id: workspace.id).first).to include(
      action: "WorkspaceNotificationBarsController#show",
      total_ms: 920.4,
      sql_queries: 18,
      status: 200
    )
  ensure
    Rails.cache.clear
  end
end
