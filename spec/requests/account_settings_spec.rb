require "rails_helper"
require "mini_magick"

RSpec.describe "Account settings", type: :request do
  def create_png(path:, width:, height:, color: "#4f46e5")
    MiniMagick::Tool.new("convert") do |convert|
      convert.size "#{width}x#{height}"
      convert.xc color
      convert << path
    end
  end

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
    expect(response.body).to include("Start account deletion request")
    expect(response.body).to include("This does not delete your account immediately.")
    expect(response.body).to include("Send deletion confirmation email")
    expect(response.body).to include('accept=".png,.jpg,.jpeg,.webp,.gif,image/png,image/jpeg,image/webp,image/gif"')
    expect(response.body).to include('data-controller="avatar-crop"')
    expect(response.body).to include("Adjust avatar")
    expect(response.body).to include('data-avatar-crop-target="previewPanel"')
    expect(response.body).to include('data-action="change-&gt;avatar-crop#open"')
    expect(response.body).to include('data-avatar-crop-target="saveButton"')
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

  it "resizes a large png avatar upload before storing it" do
    user = User.create!(email: "account-settings-avatar@example.com", password: "password123")
    workspace = Workspace.create!(name: "Account settings avatar", slug: "account-settings-avatar")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    Tempfile.create(["account-avatar", ".png"]) do |file|
      create_png(path: file.path, width: 2200, height: 1600)

      uploaded_file = Rack::Test::UploadedFile.new(file.path, "image/png")

      patch workspace_account_settings_path(workspace_slug: workspace.slug),
            params: {
              user: {
                avatar: uploaded_file
              }
            }
    end

    expect(response).to redirect_to(workspace_account_settings_path(workspace_slug: workspace.slug))
    expect(user.reload.avatar).to be_attached
    expect(user.avatar.blob.content_type).to eq("image/png")

    processed_image = MiniMagick::Image.read(user.avatar.download)
    expect(processed_image.width).to be <= Users::AvatarUploadProcessor::MAX_DIMENSION
    expect(processed_image.height).to be <= Users::AvatarUploadProcessor::MAX_DIMENSION
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

    email = ActionMailer::Base.deliveries.last
    expect(email.subject).to eq("Notae account deletion request started")
    expect(email.body.encoded).to include("A request to delete the Notae account account-settings-delete@example.com was started.")
    expect(email.body.encoded).to include("This email is a confirmation notice only. The account has not been deleted by this message.")
    expect(email.body.encoded).to include("If you started this request, keep this email as your record.")
  end
end
