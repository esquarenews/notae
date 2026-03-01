require "rails_helper"

RSpec.describe Kalendarium::WriteProposalApplier do
  def build_stack(suffix:)
    user = User.create!(email: "kal-applier-#{suffix}@example.com", password: "password123")
    workspace = Workspace.create!(name: "Kal Applier #{suffix}", slug: "kal-applier-#{suffix}")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    calendar = KalendariumCalendar.create!(
      workspace: workspace,
      created_by: user,
      name: "Main",
      color_hex: "#3B82F6",
      time_zone: "UTC",
      source_kind: "local"
    )

    [ user, workspace, calendar ]
  end

  it "creates an event for a create proposal" do
    user, workspace, calendar = build_stack(suffix: "create")
    proposal = KalendariumWriteProposal.create!(
      workspace: workspace,
      user: user,
      proposed_by: "ai_assistant",
      operation: "create",
      payload_json: {
        kalendarium_calendar_id: calendar.id,
        title: "Agent-created event",
        starts_at_utc: 2.days.from_now.iso8601,
        ends_at_utc: (2.days.from_now + 1.hour).iso8601,
        reminder_offsets_minutes: [ 10, 60 ]
      }
    )
    allow(Kalendarium::SyncCalendarJob).to receive(:perform_later)

    result = described_class.new(workspace: workspace, actor: user, proposal: proposal).call

    expect(result).to be_a(KalendariumEvent)
    expect(result.title).to eq("Agent-created event")
    expect(result.reminder_offsets_minutes).to eq([ 10, 60 ])
    expect(Kalendarium::SyncCalendarJob).to have_received(:perform_later).with(calendar.id)
  end

  it "updates an event for an update proposal" do
    user, workspace, calendar = build_stack(suffix: "update")
    event = KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      title: "Original title",
      starts_at_utc: 1.day.from_now,
      ends_at_utc: 1.day.from_now + 1.hour,
      created_by: user,
      updated_by: user,
      reminder_offsets_minutes: [ 10 ]
    )
    proposal = KalendariumWriteProposal.create!(
      workspace: workspace,
      user: user,
      proposed_by: "api",
      operation: "update",
      kalendarium_event: event,
      payload_json: {
        id: event.id,
        title: "Updated title"
      }
    )
    allow(Kalendarium::SyncCalendarJob).to receive(:perform_later)

    described_class.new(workspace: workspace, actor: user, proposal: proposal).call

    expect(event.reload.title).to eq("Updated title")
    expect(Kalendarium::SyncCalendarJob).to have_received(:perform_later).with(calendar.id)
  end

  it "deletes an event for a delete proposal" do
    user, workspace, calendar = build_stack(suffix: "delete")
    event = KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      title: "Delete me",
      starts_at_utc: 1.day.from_now,
      ends_at_utc: 1.day.from_now + 1.hour,
      created_by: user,
      updated_by: user,
      reminder_offsets_minutes: [ 10 ]
    )
    proposal = KalendariumWriteProposal.create!(
      workspace: workspace,
      user: user,
      proposed_by: "api",
      operation: "delete",
      kalendarium_event: event,
      payload_json: { id: event.id }
    )
    allow(Kalendarium::SyncCalendarJob).to receive(:perform_later)

    expect do
      described_class.new(workspace: workspace, actor: user, proposal: proposal).call
    end.to change { KalendariumEvent.where(id: event.id).count }.from(1).to(0)

    expect(Kalendarium::SyncCalendarJob).to have_received(:perform_later).with(calendar.id)
  end

  it "raises an error for unsupported operations" do
    user, workspace, = build_stack(suffix: "invalid")
    proposal = KalendariumWriteProposal.create!(
      workspace: workspace,
      user: user,
      proposed_by: "api",
      operation: "create",
      payload_json: {}
    )
    proposal.update_column(:operation, "unsupported")

    expect do
      described_class.new(workspace: workspace, actor: user, proposal: proposal).call
    end.to raise_error(described_class::Error, "Unsupported operation")
  end
end
