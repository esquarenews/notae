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

  it "enqueues sync jobs for enabled Epistula only" do
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
    end.to have_enqueued_job(Epistularium::SyncConnectionJob).with(enabled_account.id, mode: "bootstrap")

    enqueued_account_ids = enqueued_jobs
      .select { |job| job[:job] == Epistularium::SyncConnectionJob }
      .map { |job| job[:args].first }

    expect(enqueued_account_ids).to contain_exactly(enabled_account.id)
  end
end
