require "rails_helper"

RSpec.describe MeetingSession, type: :model do
  it "validates allowed capture modes/providers/statuses and active scope" do
    user = User.create!(email: "meeting-session-model-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Meeting Session Model", slug: "meeting-session-model")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    active_session = described_class.create!(
      workspace: workspace,
      title: "Active meeting",
      capture_mode: "upload",
      provider: "local",
      status: "processing",
      created_by: user,
      updated_by: user
    )
    completed_session = described_class.create!(
      workspace: workspace,
      title: "Completed meeting",
      capture_mode: "online_bot",
      provider: "google_meet",
      status: "completed",
      created_by: user,
      updated_by: user
    )

    expect(described_class.active).to include(active_session)
    expect(described_class.active).not_to include(completed_session)
    expect(active_session).to be_processing
    expect(completed_session).to be_completed
    expect(completed_session).not_to be_failed
  end
end
