require "rails_helper"
require "rake"

RSpec.describe "kalendarium:sync_due" do
  include ActiveJob::TestHelper

  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  before do
    clear_enqueued_jobs
    Notae::ScheduledTaskStore.clear_all!
    Rake::Task["kalendarium:sync_due"].reenable
  end

  it "enqueues only enabled calendar connections" do
    user = User.create!(email: "kalendarium-rake@example.com", password: "password123")
    workspace = Workspace.create!(name: "Kalendarium Rake", slug: "kalendarium-rake")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    enabled_connection = KalendariumConnection.create!(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "ics",
      label: "Enabled calendar",
      ics_url: "https://example.com/enabled.ics",
      enabled: true
    )
    KalendariumConnection.create!(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "ics",
      label: "Disabled calendar",
      ics_url: "https://example.com/disabled.ics",
      enabled: false
    )

    expect do
      Rake::Task["kalendarium:sync_due"].invoke
    end.to have_enqueued_job(Kalendarium::SyncConnectionJob).with(enabled_connection.id).on_queue("default")

    enqueued_connection_ids = enqueued_jobs
      .select { |job| job[:job] == Kalendarium::SyncConnectionJob }
      .map { |job| job[:args].first }

    expect(enqueued_connection_ids).to contain_exactly(enabled_connection.id)
  end

  it "records scheduled task telemetry for the calendar sync runner" do
    user = User.create!(email: "kalendarium-rake-telemetry@example.com", password: "password123")
    workspace = Workspace.create!(name: "Kalendarium Rake Telemetry", slug: "kalendarium-rake-telemetry")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    KalendariumConnection.create!(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "ics",
      label: "Tracked calendar",
      ics_url: "https://example.com/tracked.ics",
      enabled: true
    )

    Rake::Task["kalendarium:sync_due"].invoke

    snapshot = Notae::ScheduledTaskStore.fetch(task_name: "kalendarium:sync_due")

    expect(snapshot).to include(
      label: "Kalendarium sync dispatcher",
      cadence_label: "Every 10 minutes",
      status: :healthy,
      consecutive_failures: 0
    )
    expect(snapshot[:last_succeeded_at]).to be_present
    expect(snapshot[:last_duration_ms]).to be >= 0.0
  end
end
