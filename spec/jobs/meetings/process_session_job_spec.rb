require "rails_helper"

RSpec.describe Meetings::ProcessSessionJob, type: :job do
  include ActiveJob::TestHelper

  def build_session(suffix:)
    user = User.create!(email: "meeting-process-job-#{suffix}@example.com", password: "password123")
    workspace = Workspace.create!(name: "Meeting Process Job #{suffix}", slug: "meeting-process-job-#{suffix}")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    MeetingSession.create!(
      workspace: workspace,
      title: "Process session",
      capture_mode: "upload",
      provider: "local",
      status: "uploading",
      created_by: user,
      updated_by: user
    )
  end

  before do
    clear_enqueued_jobs
  end

  it "marks the session failed when processing raises an unexpected error" do
    session = build_session(suffix: "unexpected-error")
    pipeline = instance_double(Meetings::ProcessingPipelineService)
    allow(Meetings::ProcessingPipelineService).to receive(:new).with(session: session).and_return(pipeline)
    allow(pipeline).to receive(:call).and_raise(NoMethodError, "undefined method")

    described_class.perform_now(session.id)

    session.reload
    expect(session.status).to eq("failed")
    expect(session.error_message).to include("undefined method")
    expect(session.processed_at).to be_present
  end
end
