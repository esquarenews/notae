require "rails_helper"

RSpec.describe "Account settings", type: :request do
  it "renders account profile and deletion request controls" do
    user = User.create!(email: "account-settings@example.com", password: "password123")
    workspace = Workspace.create!(name: "Account settings", slug: "account-settings")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    get workspace_account_settings_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Account profile")
    expect(response.body).to include("Full name")
    expect(response.body).to include("Backup email")
    expect(response.body).to include("Personal bio")
    expect(response.body).to include("Request account deletion")
  end

  it "updates account profile fields" do
    user = User.create!(email: "account-settings-update@example.com", password: "password123")
    workspace = Workspace.create!(name: "Account settings update", slug: "account-settings-update")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    patch workspace_account_settings_path(workspace_slug: workspace.slug),
          params: {
            user: {
              full_name: "Errol Schmidt",
              backup_email: "backup@example.com",
              personal_bio: "Building Notae."
            }
          }

    expect(response).to redirect_to(workspace_account_settings_path(workspace_slug: workspace.slug))
    user.reload
    expect(user.full_name).to eq("Errol Schmidt")
    expect(user.backup_email).to eq("backup@example.com")
    expect(user.personal_bio).to eq("Building Notae.")
  end

  it "sends account deletion confirmation emails to the primary and backup email addresses" do
    user = User.create!(
      email: "account-settings-delete@example.com",
      password: "password123",
      backup_email: "backup-delete@example.com"
    )
    workspace = Workspace.create!(name: "Account settings delete", slug: "account-settings-delete")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    expect {
      post workspace_account_delete_request_path(workspace_slug: workspace.slug)
    }.to change { ActionMailer::Base.deliveries.count }.by(2)

    expect(response).to redirect_to(workspace_account_settings_path(workspace_slug: workspace.slug))
    recipients = ActionMailer::Base.deliveries.last(2).flat_map(&:to)
    expect(recipients).to contain_exactly("account-settings-delete@example.com", "backup-delete@example.com")
  end
end
