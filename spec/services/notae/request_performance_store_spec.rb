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
end
