require "rails_helper"

RSpec.describe "Page header features", type: :request do
  it "sets and clears a page icon, and renders it in topbar and sidebar page tree" do
    owner = User.create!(email: "page-header-icon-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Header Icon", slug: "header-icon")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Icon page")
    sign_in owner

    patch page_path(workspace_slug: workspace.slug, id: page.id),
          params: { page: { icon_action: "set", icon: "🧠" } }

    expect(response).to redirect_to(page_path(workspace_slug: workspace.slug, id: page.id))
    expect(page.reload.icon).to eq("🧠")

    get page_path(workspace_slug: workspace.slug, id: page.id)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("notae-page-icon-display")
    expect(response.body).to include("<span class=\"notae-topbar-page-icon\">🧠</span>")

    get workspace_path(workspace.slug)
    expect(response.body).to include("🧠 Icon page")

    patch page_path(workspace_slug: workspace.slug, id: page.id),
          params: { page: { icon_action: "clear" } }
    expect(page.reload.icon).to be_nil
  end

  it "supports random cover, upload cover, repositioning, and clearing" do
    owner = User.create!(email: "page-header-cover-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Header Cover", slug: "header-cover")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Cover page")
    sign_in owner

    patch page_path(workspace_slug: workspace.slug, id: page.id),
          params: { page: { cover_action: "random" } }
    expect(response).to redirect_to(page_path(workspace_slug: workspace.slug, id: page.id))
    expect(Page::COVER_PRESET_KEYS.size).to eq(12)
    Page::COVER_PRESET_KEYS.each do |key|
      expect(Rails.root.join("app/assets/images/page_covers/#{key}.svg")).to exist
    end
    expect(Page::COVER_PRESET_KEYS).to include(page.reload.cover_preset_key)
    get page_path(workspace_slug: workspace.slug, id: page.id)
    expect(response.body).to include("notae-cover-picker-grid")
    expect(response.body).to include("notae-cover-picker-quick-actions")
    expect(response.body).to include("notae-cover-picker-upload-form")

    chosen_preset = Page::COVER_PRESET_KEYS.first
    patch page_path(workspace_slug: workspace.slug, id: page.id),
          params: { page: { cover_action: "preset", cover_preset_key: chosen_preset } }
    expect(response).to redirect_to(page_path(workspace_slug: workspace.slug, id: page.id))
    expect(page.reload.cover_preset_key).to eq(chosen_preset)

    previous_focal = page.cover_focal_y
    patch page_path(workspace_slug: workspace.slug, id: page.id),
          params: { page: { cover_shift: "down" } }
    expect(page.reload.cover_focal_y).to eq([ previous_focal + 10, 100 ].min)

    Tempfile.create([ "page-cover-upload", ".png" ]) do |file|
      file.write("fake-png-content")
      file.rewind
      uploaded_file = Rack::Test::UploadedFile.new(file.path, "image/png")

      patch page_path(workspace_slug: workspace.slug, id: page.id),
            params: { page: { cover_action: "upload", cover_image: uploaded_file } }
    end

    expect(page.reload.cover_image).to be_attached
    expect(page.cover_preset_key).to be_nil

    patch page_path(workspace_slug: workspace.slug, id: page.id),
          params: { page: { cover_action: "clear" } }
    expect(page.reload.cover_preset_key).to be_nil
    expect(page.cover_image).not_to be_attached
  end

  it "renders hover action affordances and topbar comments menu with existing comments" do
    owner = User.create!(email: "page-header-comment-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Header Comment", slug: "header-comment")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Comment page")
    Comment.create!(workspace: workspace, commentable: page, author: owner, body: "First page comment")
    sign_in owner

    get page_path(workspace_slug: workspace.slug, id: page.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Add icon")
    expect(response.body).to include("Add cover")
    expect(response.body).to include("Add comment")
    expect(response.body).to include("id=\"page-comments-menu\"")
    expect(response.body).to include("notae-comments-trigger")
    expect(response.body).to include("aria-label=\"Actions\"")
    expect(response.body).to include("aria-label=\"Options\"")
    expect(response.body).to include("data-controller=\"actions-menu\"")
    expect(response.body).to include("data-actions-menu-target=\"nav\"")
    expect(response.body).to include("data-actions-menu-target=\"section\"")
    expect(response.body).to include("notae-actions-mobile-panes")
    expect(response.body).to include("data-controller=\"options-menu\"")
    expect(response.body).to include("data-options-menu-target=\"nav\"")
    expect(response.body).to include("data-options-menu-target=\"section\"")
    expect(response.body).to include("notae-options-mobile-panes")
    expect(response.body).to include("notae-actions-trigger-label")
    expect(response.body).to include("First page comment")
    expect(response.body).to include("Add a comment...")
  end
end
