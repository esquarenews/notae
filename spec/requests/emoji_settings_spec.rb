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
    expect(response.body).to include("2. Name it")
    expect(response.body).to include("placeholder=\"Party avocado\"")
    expect(response.body).to include("notae-settings-nav-item active")
  end

  it "uploads named custom emoji, highlights them as ready, and removes them" do
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
               name: "Party avocado",
               image: Rack::Test::UploadedFile.new(file.path, "image/png")
             }
           }
    end

    expect(response).to have_http_status(:found)
    expect(response.location).to include("highlight_emoji=")
    emoji = workspace.custom_emojis.last
    expect(emoji).to be_present
    expect(emoji.name).to eq("Party avocado")
    expect(emoji.image).to be_attached

    follow_redirect!
    expect(response.body).to include("Upload complete")
    expect(response.body).to include("Party Avocado is ready to use in the emoji picker.")
    expect(response.body).to include("Ready to use now")

    delete workspace_emoji_setting_path(workspace_slug: workspace.slug, id: emoji.id)

    expect(response).to redirect_to(workspace_emoji_settings_path(workspace_slug: workspace.slug))
    expect(workspace.custom_emojis.reload).to be_empty
  end

  it "requires a name when uploading a custom emoji" do
    user = User.create!(email: "emoji-settings-name-required@example.com", password: "password123")
    workspace = Workspace.create!(name: "Emoji Name Required", slug: "emoji-name-required")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    Tempfile.create([ "workspace-emoji-blank-name", ".png" ]) do |file|
      file.write("fake-png-content")
      file.rewind

      post workspace_emoji_settings_path(workspace_slug: workspace.slug),
           params: {
             workspace_emoji: {
               name: "",
               image: Rack::Test::UploadedFile.new(file.path, "image/png")
             }
           }
    end

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Upload incomplete")
    expect(response.body).to include("Name can&#39;t be blank")
  end

  it "rejects SVG custom emoji uploads" do
    user = User.create!(email: "emoji-settings-svg@example.com", password: "password123")
    workspace = Workspace.create!(name: "Emoji SVG", slug: "emoji-settings-svg")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    Tempfile.create([ "workspace-emoji", ".svg" ]) do |file|
      file.write("<svg></svg>")
      file.rewind

      post workspace_emoji_settings_path(workspace_slug: workspace.slug),
           params: {
             workspace_emoji: {
               name: "Unsafe",
               image: Rack::Test::UploadedFile.new(file.path, "image/svg+xml")
             }
           }
    end

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Emoji image type is not supported.")
    expect(workspace.custom_emojis.reload).to be_empty
  end
end
