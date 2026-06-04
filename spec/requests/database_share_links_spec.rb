require "rails_helper"

RSpec.describe "DatabaseShareLinks", type: :request do
  it "defaults new grid share links to read-only access" do
    owner = User.create!(email: "database-share-links-default-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Grid public share default", slug: "grid-public-share-default")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Default shareable grid")
    sign_in owner

    post database_share_links_path(workspace_slug: workspace.slug, database_id: database.id)

    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id, options_menu: "open"))
    expect(DatabaseShareLink.recent_first.first.access_level).to eq("read_only")
  end

  it "allows grid managers to create and revoke public links" do
    owner = User.create!(email: "database-share-links-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Grid public share", slug: "grid-public-share")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Shareable grid")
    sign_in owner

    post database_share_links_path(workspace_slug: workspace.slug, database_id: database.id),
         params: { database_share_link: { expires_at: 2.days.from_now, access_level: "edit" } }

    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id, options_menu: "open"))
    share_link = DatabaseShareLink.recent_first.first
    expect(share_link.database_id).to eq(database.id)
    expect(share_link.token).to be_present
    expect(share_link.access_level).to eq("edit")
    expect(AuditEvent.recent_first.first.metadata).to include(
      "kind" => "public_grid_share_link_created",
      "access_level" => "edit"
    )

    delete database_share_link_path(workspace_slug: workspace.slug, database_id: database.id, id: share_link.id)

    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id, options_menu: "open"))
    expect(share_link.reload.revoked_at).to be_present
    expect(AuditEvent.recent_first.first.metadata["kind"]).to eq("public_grid_share_link_revoked")
  end

  it "prevents non-managers from creating public grid links" do
    owner = User.create!(email: "database-share-links-policy-owner@example.com", password: "password123")
    member = User.create!(email: "database-share-links-policy-member@example.com", password: "password123")
    workspace = Workspace.create!(name: "Grid policy share", slug: "grid-policy-share")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: workspace, user: member, role: :member)
    database = Database.create!(workspace: workspace, name: "Manager-only grid")
    sign_in member

    post database_share_links_path(workspace_slug: workspace.slug, database_id: database.id)

    expect(response).to redirect_to(root_path)
    expect(DatabaseShareLink.count).to eq(0)
  end
end
