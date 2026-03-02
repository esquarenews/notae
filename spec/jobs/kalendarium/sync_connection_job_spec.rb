require "rails_helper"

RSpec.describe Kalendarium::SyncConnectionJob, type: :job do
  def build_connection(suffix:)
    user = User.create!(email: "kal-sync-connection-job-#{suffix}@example.com", password: "password123")
    workspace = Workspace.create!(name: "Kal Sync Connection Job #{suffix}", slug: "kal-sync-connection-job-#{suffix}")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    KalendariumConnection.create!(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "icloud_caldav",
      label: "iCloud sync #{suffix}",
      provider_username: "apple-id@example.com",
      provider_password: "aaaa-bbbb-cccc-dddd",
      enabled: true,
      status: "connected"
    )
  end

  it "auto-disables the connection on permanent authentication failures" do
    connection = build_connection(suffix: "auth-failure")
    sync_service = instance_double(Kalendarium::ConnectionSyncService)
    allow(Kalendarium::ConnectionSyncService).to receive(:new).with(connection: connection).and_return(sync_service)
    allow(sync_service).to receive(:call).and_raise(RuntimeError, "CalDAV authentication failed (403). Use Apple ID email and an app-specific password.")

    expect do
      described_class.perform_now(connection.id)
    end.not_to raise_error

    connection.reload
    expect(connection.enabled).to be(false)
    expect(connection.status).to eq("sync_error")
    expect(connection.last_error).to include("CalDAV authentication failed (403)")
    expect(connection.last_error).to include("Auto-disabled after authentication failure")
  end

  it "re-raises transient failures so normal retries still apply" do
    connection = build_connection(suffix: "transient-failure")
    sync_service = instance_double(Kalendarium::ConnectionSyncService)
    allow(Kalendarium::ConnectionSyncService).to receive(:new).with(connection: connection).and_return(sync_service)
    allow(sync_service).to receive(:call).and_raise(RuntimeError, "Net::ReadTimeout while contacting provider")

    expect do
      described_class.perform_now(connection.id)
    end.to raise_error(RuntimeError, "Net::ReadTimeout while contacting provider")

    expect(connection.reload.enabled).to be(true)
  end

  it "skips duplicate sync attempts while a lock already exists" do
    connection = build_connection(suffix: "duplicate-lock")
    sync_service = instance_double(Kalendarium::ConnectionSyncService)
    allow(Kalendarium::ConnectionSyncService).to receive(:new).with(connection: connection).and_return(sync_service)
    allow(sync_service).to receive(:call)
    lock_key = "kalendarium:sync_connection:#{connection.id}"
    allow(Rails.cache).to receive(:write).with(lock_key, true, unless_exist: true, expires_in: 10.minutes).and_return(false)
    allow(Rails.cache).to receive(:delete).with(lock_key).and_return(true)

    described_class.perform_now(connection.id)

    expect(sync_service).not_to have_received(:call)
  end
end
