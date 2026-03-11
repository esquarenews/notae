require "rails_helper"

RSpec.describe Search::PersistKnowledgeSuggestionService do
  include ActiveSupport::Testing::TimeHelpers

  it "keys daily summaries by the user's local date" do
    user = User.create!(
      email: "persist-knowledge@example.com",
      password: "password123",
      time_zone: "Australia/Melbourne"
    )
    workspace = Workspace.create!(name: "Persist knowledge", slug: "persist-knowledge")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    service = described_class.new(user: user, workspace: workspace, kind: KnowledgeSuggestion::KIND_DAILY_SUMMARY)

    travel_to Time.utc(2026, 3, 11, 20, 45, 0) do
      expect(service.send(:current_local_date)).to eq(Date.new(2026, 3, 12))
    end
  end
end
