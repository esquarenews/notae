require "rails_helper"

RSpec.describe "Emoji settings", type: :request do
  it "renders the workspace emoji upload page" do
    user = User.create!(email: "emoji-settings-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Emoji Workspace", slug: "emoji-settings-workspace")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    get workspace_emoji_settings_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Upload custom emoji")
    expect(response.body).to include("Workspace custom emoji")
    expect(response.body).to include("notae-settings-nav-item active")
  end

  it "uploads and removes custom emoji for a workspace" do
    user = User.create!(email: "emoji-settings-update@example.com", password: "password123")
    workspace = Workspace.create!(name: "Emoji Update", slug: "emoji-settings-update")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    Tempfile.create([ "workspace-emoji", ".png" ]) do |file|
      file.write("fake-png-content")
      file.rewind

      post workspace_emoji_settings_path(workspace_slug: workspace.slug),
           params: {
             workspace_emoji: {
               image: Rack::Test::UploadedFile.new(file.path, "image/png")
             }
           }
    end

    expect(response).to redirect_to(workspace_emoji_settings_path(workspace_slug: workspace.slug))
    emoji = workspace.custom_emojis.last
    expect(emoji).to be_present
    expect(emoji.image).to be_attached

    delete workspace_emoji_setting_path(workspace_slug: workspace.slug, id: emoji.id)

    expect(response).to redirect_to(workspace_emoji_settings_path(workspace_slug: workspace.slug))
    expect(workspace.custom_emojis.reload).to be_empty
  end
end
