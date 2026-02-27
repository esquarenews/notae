require "rails_helper"

RSpec.describe "Pages", type: :request do
  it "creates nested pages and renders hierarchy in workspace sidebar" do
    owner = User.create!(email: "pages-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Knowledge", slug: "knowledge")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    parent = Page.create!(workspace: workspace, created_by: owner, title: "Parent Page")
    sign_in owner

    post pages_path(workspace_slug: workspace.slug), params: { page: { title: "Child Page", parent_page_id: parent.id } }

    expect(response).to have_http_status(:redirect)
    get workspace_path(workspace.slug)
    expect(response.body).to include("Parent Page")
    expect(response.body).to include("Child Page")
  end

  it "hides archived pages from workspace sidebar" do
    owner = User.create!(email: "pages-archive-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Private", slug: "private")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Archive me")
    sign_in owner

    patch archive_page_path(workspace_slug: workspace.slug, id: page.id)
    get workspace_path(workspace.slug)

    expect(response.body).not_to include("Archive me")
  end

  it "supports page-level permission overrides: private, workspace, specific users" do
    owner = User.create!(email: "page-perms-owner@example.com", password: "password123")
    member = User.create!(email: "page-perms-member@example.com", password: "password123")
    outsider = User.create!(email: "page-perms-outsider@example.com", password: "password123")
    workspace = Workspace.create!(name: "Perms", slug: "perms")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: workspace, user: member, role: :member)
    Membership.create!(workspace: workspace, user: outsider, role: :member)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Visibility Doc")

    sign_in owner
    patch permissions_page_path(workspace_slug: workspace.slug, id: page.id),
          params: { page: { permission_mode: "private_page" } }
    expect(response).to redirect_to(page_path(workspace_slug: workspace.slug, id: page.id))
    expect(AuditEvent.recent_first.first.action).to eq("share")

    sign_out owner
    sign_in member
    get page_path(workspace_slug: workspace.slug, id: page.id)
    expect(response).to have_http_status(:not_found)

    sign_out member
    sign_in owner
    patch permissions_page_path(workspace_slug: workspace.slug, id: page.id),
          params: { page: { permission_mode: "shared_to_workspace" } }
    sign_out owner
    sign_in member
    get page_path(workspace_slug: workspace.slug, id: page.id)
    expect(response).to have_http_status(:ok)

    sign_out member
    sign_in owner
    patch permissions_page_path(workspace_slug: workspace.slug, id: page.id),
          params: { page: { permission_mode: "specific_users", shared_user_ids: [ member.id ] } }
    sign_out owner

    sign_in member
    get page_path(workspace_slug: workspace.slug, id: page.id)
    expect(response).to have_http_status(:ok)

    sign_out member
    sign_in outsider
    get page_path(workspace_slug: workspace.slug, id: page.id)
    expect(response).to have_http_status(:not_found)
  end

  it "blocks cross-workspace page access attempts" do
    owner = User.create!(email: "page-owner-cross@example.com", password: "password123")
    intruder = User.create!(email: "page-intruder-cross@example.com", password: "password123")
    workspace = Workspace.create!(name: "Cross", slug: "cross")
    other_workspace = Workspace.create!(name: "Other", slug: "other")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: other_workspace, user: intruder, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Protected")

    sign_in intruder
    get page_path(workspace_slug: workspace.slug, id: page.id)

    expect(response).to have_http_status(:not_found)
  end

  it "renders global shortcut UI containers on page view" do
    owner = User.create!(email: "page-shortcuts-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Shortcuts", slug: "shortcuts")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Shortcuts page")
    sign_in owner

    get page_path(workspace_slug: workspace.slug, id: page.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("notae-sidebar-scroll")
    expect(response.body).to include("notae-content-scroll")
    expect(response.body).to include("notae-ai-rail")
    expect(response.body).to include("Quick switcher")
    expect(response.body).to include("Keyboard shortcuts")
    expect(response.body).to include("Cmd/Ctrl + K")
  end

  it "includes the compiled app stylesheet and keeps the tailwind entrypoint present" do
    tailwind_entrypoint = Rails.root.join("app/assets/tailwind/application.css")
    expect(tailwind_entrypoint).to exist
    expect(tailwind_entrypoint.read).to include('@import "tailwindcss";')

    owner = User.create!(email: "page-tailwind-layout-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Tailwind layout", slug: "tailwind-layout")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Page.create!(workspace: workspace, created_by: owner, title: "Tailwind page")
    sign_in owner

    get workspace_path(workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to match(%r{href="[^"]*/assets/application[^"]*\.css"})
  end

  it "renders sidebar create menu with Nota, grid, meeting, and workspace options plus icons" do
    owner = User.create!(email: "page-sidebar-create-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Sidebar create", slug: "sidebar-create")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Page.create!(workspace: workspace, created_by: owner, title: "Landing")
    sign_in owner

    get workspace_path(workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("New Nota")
    expect(response.body).to include("New grid")
    expect(response.body).to include("New meeting")
    expect(response.body).to include("New Workspace")
    expect(response.body).to include("notae-create-menu-icon-page")
    expect(response.body).to include("notae-create-menu-icon-database")
    expect(response.body).to include("notae-create-menu-icon-meeting")
    expect(response.body).to include("notae-create-menu-icon-workspace")
    expect(response.body).to include("data-shell-target=\"workspaceDialog\"")
  end

  it "keeps create redirects working even if another workspace has a blank slug" do
    owner = User.create!(email: "page-create-blank-slug-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Create target", slug: "create-target")
    stale_workspace = Workspace.create!(name: "Stale workspace", slug: "stale-workspace")
    stale_workspace.update_column(:slug, "")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: stale_workspace, user: owner, role: :owner)
    sign_in owner

    post pages_path(workspace_slug: workspace.slug), params: { page: { title: "Created from menu" } }

    created_page = Page.order(created_at: :desc).first
    expect(created_page.title).to eq("Created from menu")
    expect(response).to redirect_to(page_path(workspace_slug: workspace.slug, id: created_page.id))

    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Created from menu")
  end

  it "renders grids in the sidebar with each grid icon appended to the title" do
    owner = User.create!(email: "page-sidebar-grid-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Sidebar grids", slug: "sidebar-grids")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Database.create!(workspace: workspace, name: "Campaign grid", icon: "🧠")
    sign_in owner

    get workspace_path(workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Grids")
    expect(response.body).to include("🧠 Campaign grid")
  end

  it "renders a document-first page canvas with topbar options menu" do
    owner = User.create!(email: "page-document-layout-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Document layout", slug: "document-layout")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "New page")
    sign_in owner

    get page_path(workspace_slug: workspace.slug, id: page.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Options")
    expect(response.body).to include("Actions")
    expect(response.body).to include("notae-actions-menu")
    expect(response.body).to include("notae-doc-canvas")
    expect(response.body).to include("notae-page-title-input")
    expect(response.body).to include("Turn into")
    expect(response.body).to include("Block equation")
    expect(response.body).to include("Synced block")
  end

  it "updates actions settings on a page and duplicates the page with blocks" do
    owner = User.create!(email: "page-actions-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Actions", slug: "actions")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Action page")
    page.blocks.create!(workspace: workspace, created_by: owner, block_type: "paragraph")
    sign_in owner

    patch page_path(workspace_slug: workspace.slug, id: page.id),
          params: {
            page: {
              font_style: "mono",
              small_text: "true",
              full_width: "true",
              suggest_edits: "true",
              locked: "true"
            }
          }

    expect(response).to redirect_to(page_path(workspace_slug: workspace.slug, id: page.id))
    expect(page.reload.font_style).to eq("mono")
    expect(page.small_text).to be(true)
    expect(page.full_width).to be(true)
    expect(page.suggest_edits).to be(true)
    expect(page.locked).to be(true)

    expect do
      post duplicate_page_path(workspace_slug: workspace.slug, id: page.id)
    end.to change(Page, :count).by(1)
       .and change(Block, :count).by(1)

    expect(response).to redirect_to(page_path(workspace_slug: workspace.slug, id: Page.order(:created_at).last.id))

    duplicated_page = Page.order(:created_at).last
    expect(duplicated_page.title).to eq("Action page (copy)")
    expect(duplicated_page.font_style).to eq("mono")
    expect(duplicated_page.small_text).to be(true)
    expect(duplicated_page.full_width).to be(true)
    expect(duplicated_page.suggest_edits).to be(true)
    expect(duplicated_page.locked).to be(false)
    expect(duplicated_page.blocks.active.count).to eq(1)
  end

  it "keeps actions and options menus open when requested and renders options icon" do
    owner = User.create!(email: "page-menu-open-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Menu Open", slug: "menu-open")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Menu open page")
    sign_in owner

    patch page_path(workspace_slug: workspace.slug, id: page.id, actions_menu: "open"),
          params: { page: { small_text: "true" } }
    expect(response).to redirect_to(page_path(workspace_slug: workspace.slug, id: page.id, actions_menu: "open"))
    follow_redirect!
    expect(response.body).to match(/id="page-actions-menu"[^>]*open/)

    patch permissions_page_path(workspace_slug: workspace.slug, id: page.id, options_menu: "open"),
          params: { page: { permission_mode: "shared_to_workspace" } }
    expect(response).to redirect_to(page_path(workspace_slug: workspace.slug, id: page.id, options_menu: "open"))
    follow_redirect!
    expect(response.body).to match(/id="page-options-menu"[^>]*open/)
    expect(response.body).to include("⚙")
  end

  it "updates page title from the clean page header" do
    owner = User.create!(email: "page-title-update-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Title update", slug: "title-update")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Untitled")
    sign_in owner

    patch page_path(workspace_slug: workspace.slug, id: page.id),
          params: { page: { title: "Project brief" } }

    expect(response).to redirect_to(page_path(workspace_slug: workspace.slug, id: page.id))
    expect(page.reload.title).to eq("Project brief")
  end

  it "updates page title through json endpoint for autosave" do
    owner = User.create!(email: "page-title-json-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Title json", slug: "title-json")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Untitled")
    sign_in owner

    patch page_path(workspace_slug: workspace.slug, id: page.id),
          params: { page: { title: "Autosaved title" } },
          as: :json

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["title"]).to eq("Autosaved title")
    expect(page.reload.title).to eq("Autosaved title")
  end
end
