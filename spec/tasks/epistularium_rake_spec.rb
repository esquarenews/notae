require "rails_helper"
require "rake"

RSpec.describe "epistularium:sync_due" do
  include ActiveJob::TestHelper

  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  before do
    clear_enqueued_jobs
    Rake::Task["epistularium:sync_due"].reenable
  end

  it "enqueues only enabled Epistula and uses bootstrap for never-synced mailboxes" do
    user = User.create!(email: "epistularium-rake@example.com", password: "password123")
    workspace = Workspace.create!(name: "Epistularium Rake", slug: "epistularium-rake")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    enabled_account = EpistulariumAccount.create!(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "imap",
      label: "Enabled inbox",
      provider_username: "enabled@example.com",
      provider_password: "secret",
      enabled: true,
      settings_json: { "imap_host" => "imap.example.com" }
    )
    EpistulariumAccount.create!(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "imap",
      label: "Disabled inbox",
      provider_username: "disabled@example.com",
      provider_password: "secret",
      enabled: false,
      settings_json: { "imap_host" => "imap.example.com" }
    )

    expect do
      Rake::Task["epistularium:sync_due"].invoke
    end.to have_enqueued_job(Epistularium::SyncConnectionJob).with(enabled_account.id, mode: "bootstrap").on_queue("default")

    enqueued_account_ids = enqueued_jobs
      .select { |job| job[:job] == Epistularium::SyncConnectionJob }
      .map { |job| job[:args].first }

    expect(enqueued_account_ids).to contain_exactly(enabled_account.id)
  end

  it "prioritizes incremental refresh but still routes overdue backfill to the low-priority queue" do
    user = User.create!(email: "epistularium-rake-priority@example.com", password: "password123")
    workspace = Workspace.create!(name: "Epistularium Rake Priority", slug: "epistularium-rake-priority")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    fresh_due_account = EpistulariumAccount.create!(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "gmail",
      label: "Gmail inbox",
      access_token: "gmail-token",
      enabled: true,
      settings_json: {
        "last_fresh_sync_at" => 11.minutes.ago.iso8601,
        "last_backfill_sync_at" => 20.minutes.ago.iso8601
      }
    )
    EpistulariumMessage.create!(
      workspace: workspace,
      epistularium_account: fresh_due_account,
      provider_message_id: "msg-rake-fresh-due",
      mailbox: "inbox",
      subject: "Existing message",
      from_email: "alex@example.com",
      body_text: "Existing body"
    )

    backfill_due_account = EpistulariumAccount.create!(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "imap",
      label: "IMAP inbox",
      provider_username: "imap@example.com",
      provider_password: "secret",
      enabled: true,
      settings_json: {
        "imap_host" => "imap.example.com",
        "last_fresh_sync_at" => 3.minutes.ago.iso8601,
        "last_backfill_sync_at" => 61.minutes.ago.iso8601
      }
    )
    EpistulariumMessage.create!(
      workspace: workspace,
      epistularium_account: backfill_due_account,
      provider_message_id: "msg-rake-backfill-due",
      mailbox: "inbox",
      subject: "Existing message",
      from_email: "alex@example.com",
      body_text: "Existing body"
    )

    Rake::Task["epistularium:sync_due"].invoke

    expect(enqueued_jobs).to include(
      a_hash_including(
        job: Epistularium::SyncConnectionJob,
        queue: "default",
        args: [ fresh_due_account.id, a_hash_including("mode" => "incremental") ]
      ),
      a_hash_including(
        job: Epistularium::SyncConnectionJob,
        queue: "epistularium_backfill",
        args: [ backfill_due_account.id, a_hash_including("mode" => "full_backfill") ]
      )
    )
  end
end
