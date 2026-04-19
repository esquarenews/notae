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
    expect(response.body).to include("API access tokens")
    expect(response.body).to include("Create token")
    expect(response.body).to include("Recent token audit activity")
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

  it "updates account profile fields over turbo stream without redirecting" do
    user = User.create!(email: "account-settings-update-turbo@example.com", password: "password123")
    workspace = Workspace.create!(name: "Account settings update turbo", slug: "account-settings-update-turbo")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    patch workspace_account_settings_path(workspace_slug: workspace.slug),
          params: {
            user: {
              full_name: "Turbo Errol",
              backup_email: "turbo@example.com",
              personal_bio: "Turbo profile update."
            }
          },
          as: :turbo_stream

    expect(response).to have_http_status(:ok)
    expect(response).not_to be_redirect
    expect(response.media_type).to eq(Mime[:turbo_stream].to_s)
    expect(response.body).to include('turbo-stream action="replace" target="settings_flash_messages"')
    expect(response.body).to include('turbo-stream action="replace" target="account_settings_content"')
    expect(response.body).to include("Account settings updated.")

    user.reload
    expect(user.full_name).to eq("Turbo Errol")
    expect(user.backup_email).to eq("turbo@example.com")
    expect(user.personal_bio).to eq("Turbo profile update.")
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

  it "sends account deletion confirmation over turbo stream without redirecting" do
    user = User.create!(
      email: "account-settings-delete-turbo@example.com",
      password: "password123",
      backup_email: "backup-delete-turbo@example.com"
    )
    workspace = Workspace.create!(name: "Account settings delete turbo", slug: "account-settings-delete-turbo")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    expect {
      post workspace_account_delete_request_path(workspace_slug: workspace.slug), as: :turbo_stream
    }.to change { ActionMailer::Base.deliveries.count }.by(2)

    expect(response).to have_http_status(:ok)
    expect(response).not_to be_redirect
    expect(response.media_type).to eq(Mime[:turbo_stream].to_s)
    expect(response.body).to include('turbo-stream action="replace" target="settings_flash_messages"')
    expect(response.body).to include("Account deletion confirmation sent to")
    expect(response.body).to include("account-settings-delete-turbo@example.com")
    expect(response.body).to include("backup-delete-turbo@example.com")
  end

  it "creates a scoped API token from account settings and reveals it once" do
    user = User.create!(email: "account-settings-api-token@example.com", password: "password123")
    workspace = Workspace.create!(name: "Account settings API token", slug: "account-settings-api-token")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    expect {
      post workspace_account_api_tokens_path(workspace_slug: workspace.slug),
           params: {
             api_token: {
               name: "Codex MCP",
               expires_at: 30.days.from_now.strftime("%Y-%m-%dT%H:%M"),
               scopes_json: [ ApiToken::SCOPE_PAGES_READ, ApiToken::SCOPE_NOTIFICATIONS_WRITE ]
             }
           },
           as: :turbo_stream
    }.to change(ApiToken, :count).by(1)
      .and change(ApiTokenAuditEvent, :count).by(1)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq(Mime[:turbo_stream].to_s)
    expect(response.body).to include("API token created. Copy it now because it will not be shown again.")
    expect(response.body).to include("Copy this token now")
    expect(response.body).to include("Codex MCP")

    token = user.api_tokens.order(:created_at).last
    expect(token.scopes).to contain_exactly(ApiToken::SCOPE_PAGES_READ, ApiToken::SCOPE_NOTIFICATIONS_WRITE)
    expect(token.expires_at).to be_present
  end

  it "revokes an API token from account settings" do
    user = User.create!(email: "account-settings-api-token-revoke@example.com", password: "password123")
    workspace = Workspace.create!(name: "Account settings API revoke", slug: "account-settings-api-revoke")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    token = user.api_tokens.create!(name: "Codex MCP", scopes_json: [ ApiToken::SCOPE_PAGES_READ ])
    sign_in user

    expect {
      post workspace_account_api_token_revoke_path(workspace_slug: workspace.slug, id: token.id), as: :turbo_stream
    }.to change(ApiTokenAuditEvent, :count).by(1)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("API token revoked.")
    expect(token.reload.revoked_at).to be_present
  end

  it "rotates an API token from account settings and returns the replacement" do
    user = User.create!(email: "account-settings-api-token-rotate@example.com", password: "password123")
    workspace = Workspace.create!(name: "Account settings API rotate", slug: "account-settings-api-rotate")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    token = user.api_tokens.create!(
      name: "Codex MCP",
      scopes_json: [ ApiToken::SCOPE_PAGES_READ, ApiToken::SCOPE_NOTIFICATIONS_WRITE ],
      expires_at: 14.days.from_now
    )
    sign_in user

    expect {
      post workspace_account_api_token_rotate_path(workspace_slug: workspace.slug, id: token.id), as: :turbo_stream
    }.to change(ApiToken, :count).by(1)
      .and change(ApiTokenAuditEvent, :count).by(2)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("API token rotated. Copy the replacement now because it will not be shown again.")
    expect(response.body).to include("Copy this token now")

    replacement = user.api_tokens.order(:created_at).last
    expect(replacement.id).not_to eq(token.id)
    expect(replacement.scopes).to eq(token.scopes)
    expect(token.reload.revoked_at).to be_present
  end
end
