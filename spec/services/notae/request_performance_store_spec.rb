require "rails_helper"

RSpec.describe Notae::RequestPerformanceStore do
  around do |example|
    Rails.cache.clear
    example.run
    Rails.cache.clear
  end

  it "stores the newest samples first and trims the list" do
    workspace = Workspace.create!(name: "Performance Store", slug: "performance-store")

    (Notae::RequestPerformanceStore::MAX_SAMPLES + 2).times do |index|
      described_class.record!(
        workspace_id: workspace.id,
        sample: {
          action: "PagesController#show",
          path: "/w/#{workspace.slug}/pages/#{index}",
          total_ms: 100 + index,
          sql_queries: index,
          sql_ms: 10 + index,
          status: 200,
          recorded_at: Time.zone.parse("2026-04-18 10:00:00") + index.minutes
        }
      )
    end

    samples = described_class.fetch(workspace_id: workspace.id)

    expect(samples.size).to eq(Notae::RequestPerformanceStore::MAX_SAMPLES)
    expect(samples.first[:path]).to eq("/w/#{workspace.slug}/pages/#{Notae::RequestPerformanceStore::MAX_SAMPLES + 1}")
    expect(samples.last[:path]).to eq("/w/#{workspace.slug}/pages/2")
  end

  it "evaluates request samples against action budgets" do
    healthy_sample = {
      action: "WorkspaceHomeController#show",
      path: "/w/performance-store",
      total_ms: 420.0,
      sql_queries: 22,
      sql_ms: 81.0,
      status: 200,
      recorded_at: Time.zone.parse("2026-04-19 09:00:00")
    }
    over_budget_sample = healthy_sample.merge(total_ms: 910.0, sql_queries: 72, sql_ms: 310.0)

    expect(described_class.budget_for(action: "WorkspaceHomeController#show")).to include(
      total_ms: 700.0,
      sql_ms: 180.0,
      sql_queries: 45
    )
    expect(described_class.budget_for(action: "SearchesController#index")).to include(
      total_ms: 650.0,
      sql_ms: 180.0,
      sql_queries: 40
    )
    expect(described_class.budget_for(action: "EpistulariumController#show")).to include(
      total_ms: 850.0,
      sql_ms: 240.0,
      sql_queries: 55
    )
    expect(described_class.budget_for(action: "NotificationsController#index")).to include(
      total_ms: 500.0,
      sql_ms: 140.0,
      sql_queries: 35
    )
    expect(described_class.budget_for(action: "PagesController#show")).to include(
      total_ms: 900.0,
      sql_ms: 260.0,
      sql_queries: 80
    )
    expect(described_class.budget_for(action: "WorkspaceNotificationBarsController#show")).to include(
      total_ms: 350.0,
      sql_ms: 120.0,
      sql_queries: 25
    )
    expect(described_class.budget_for(action: "AiAssistantController#updates")).to include(
      total_ms: 350.0,
      sql_ms: 120.0,
      sql_queries: 25
    )
    expect(described_class.budget_status(healthy_sample)).to eq(:healthy)
    expect(described_class.budget_breaches(healthy_sample)).to eq([])

    expect(described_class.budget_status(over_budget_sample)).to eq(:over_budget)
    expect(described_class.budget_breaches(over_budget_sample)).to contain_exactly("total time", "sql time", "sql queries")
  end
end
