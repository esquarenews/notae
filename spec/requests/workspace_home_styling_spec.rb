require "rails_helper"

RSpec.describe "Workspace home styling", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  it "renders the branded workspace home layout" do
    owner = User.create!(email: "workspace-home-style-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Workspace Styled", slug: "workspace-styled")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(
      workspace: workspace,
      created_by: owner,
      title: "Brand card page",
      icon: "🚀",
      cover_preset_key: Page::COVER_PRESET_KEYS.first
    )
    Database.create!(workspace: workspace, name: "Design DB")
    AuditEvent.create!(
      workspace: workspace,
      actor: owner,
      action: "share",
      metadata: { kind: "spec_event", page_id: page.id }
    )
    sign_in owner

    get workspace_path(workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("notae-workspace-home")
    expect(response.body).to include("notae-workspace-home-search")
    expect(response.body).to include("notae-workspace-page-card")
    expect(response.body).to include("notae-workspace-page-card-cover")
    expect(response.body).to include("🚀")

    body = response.body
    search_index = body.index("Search pages, blocks, and rows")
    create_page_index = body.index("<h2>Create page</h2>")
    pages_index = body.index("<h2>Pages</h2>")
    databases_index = body.index("<h2>Grids</h2>")
    members_index = body.index("<h2>Members</h2>")
    invite_index = body.index("<h2>Invite people</h2>")
    audit_index = body.index("<h2>Recent audit events</h2>")

    expect(search_index).to be < create_page_index
    expect(create_page_index).to be < pages_index
    expect(pages_index).to be < databases_index
    expect(databases_index).to be < members_index
    expect(members_index).to be < invite_index
    expect(invite_index).to be < audit_index
  end

  it "updates greeting by time of day" do
    owner = User.create!(email: "workspace-home-greeting-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Greeting Styled", slug: "greeting-styled")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    sign_in owner

    travel_to(Time.zone.local(2026, 2, 25, 9, 0, 0)) do
      get workspace_path(workspace.slug)
      expect(response.body).to include("Good morning")
    end

    travel_to(Time.zone.local(2026, 2, 25, 14, 0, 0)) do
      get workspace_path(workspace.slug)
      expect(response.body).to include("Good afternoon")
    end

    travel_to(Time.zone.local(2026, 2, 25, 20, 0, 0)) do
      get workspace_path(workspace.slug)
      expect(response.body).to include("Good evening")
    end
  end

  it "opens the last visited page when open-on-start is set to last page visited" do
    owner = User.create!(
      email: "workspace-home-last-visited@example.com",
      password: "password123",
      open_on_start_preference: "last_visited_page"
    )
    workspace = Workspace.create!(name: "Last visited", slug: "last-visited")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Visited page")
    sign_in owner

    get page_path(workspace_slug: workspace.slug, id: page.id)
    expect(response).to have_http_status(:ok)

    get workspace_path(workspace.slug)
    expect(response).to redirect_to(page_path(workspace_slug: workspace.slug, id: page.id))
  end
end
