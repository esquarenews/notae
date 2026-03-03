require "rails_helper"

RSpec.describe Meetings::NotaMaterializerService do
  def build_stack(suffix:)
    user = User.create!(email: "meeting-nota-materializer-#{suffix}@example.com", password: "password123")
    workspace = Workspace.create!(name: "Meeting Materializer #{suffix}", slug: "meeting-materializer-#{suffix}")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    calendar = KalendariumCalendar.create!(
      workspace: workspace,
      created_by: user,
      name: "Main",
      color_hex: "#3B82F6",
      time_zone: "UTC",
      source_kind: "local"
    )
    event = KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      created_by: user,
      updated_by: user,
      title: "Planning sync",
      starts_at_utc: 1.hour.from_now,
      ends_at_utc: 2.hours.from_now
    )
    session = MeetingSession.create!(
      workspace: workspace,
      kalendarium_event: event,
      title: "Planning sync notes",
      capture_mode: "upload",
      provider: "local",
      status: "processing",
      created_by: user,
      updated_by: user
    )

    [ user, workspace, event, session ]
  end

  it "creates a linked meeting note page and persists session output idempotently" do
    user, workspace, event, session = build_stack(suffix: "output")
    service = described_class.new(session: session, actor: user)

    page = service.ensure_linked_nota!
    expect(page.workspace_id).to eq(workspace.id)
    expect(page.page_kind).to eq("meeting_note")
    expect(page.title).to include("Planning sync")

    first_page = service.upsert_session_output!(
      transcript_text: "[00:00] Speaker 1: Hello team",
      summary_markdown: "### Summary\n- Kickoff",
      action_items: [ { "title" => "Send deck", "owner" => "Alex", "due_at" => 1.day.from_now.iso8601 } ]
    )
    first_blocks = first_page.blocks.active.where("content_json ->> 'notae_meeting_session_id' = ?", session.id.to_s)
    expect(first_blocks.count).to be >= 3

    second_page = service.upsert_session_output!(
      transcript_text: "[00:00] Speaker 1: Updated transcript",
      summary_markdown: "### Summary\n- Updated",
      action_items: []
    )
    second_blocks = second_page.blocks.active.where("content_json ->> 'notae_meeting_session_id' = ?", session.id.to_s)
    expect(second_blocks.count).to be >= 2
    expect(second_blocks.pluck(:search_text).join(" ")).to include("Updated transcript")

    expect(event.reload.linked_page_id).to be_nil
  end
end
