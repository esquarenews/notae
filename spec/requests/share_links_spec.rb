require "rails_helper"

RSpec.describe "ShareLinks", type: :request do
  it "defaults new page share links to read-only access" do
    owner = User.create!(email: "share-links-default-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Public share default", slug: "public-share-default")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Default shareable page")
    sign_in owner

    post page_share_links_path(workspace_slug: workspace.slug, page_id: page.id)

    expect(response).to redirect_to(page_path(workspace_slug: workspace.slug, id: page.id))
    expect(ShareLink.recent_first.first.access_level).to eq("read_only")
  end

  it "allows page managers to create and revoke public links" do
    owner = User.create!(email: "share-links-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Public share", slug: "public-share")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Shareable page")
    sign_in owner

    post page_share_links_path(workspace_slug: workspace.slug, page_id: page.id),
         params: { share_link: { expires_at: 2.days.from_now, access_level: "comment" } }

    expect(response).to redirect_to(page_path(workspace_slug: workspace.slug, id: page.id))
    share_link = ShareLink.recent_first.first
    expect(share_link.page_id).to eq(page.id)
    expect(share_link.token).to be_present
    expect(share_link.access_level).to eq("comment")
    expect(AuditEvent.recent_first.first.metadata).to include(
      "kind" => "public_share_link_created",
      "access_level" => "comment"
    )

    delete page_share_link_path(workspace_slug: workspace.slug, page_id: page.id, id: share_link.id)

    expect(response).to redirect_to(page_path(workspace_slug: workspace.slug, id: page.id))
    expect(share_link.reload.revoked_at).to be_present
    expect(AuditEvent.recent_first.first.metadata["kind"]).to eq("public_share_link_revoked")
  end

  it "prevents non-managers from creating public links" do
    owner = User.create!(email: "share-links-policy-owner@example.com", password: "password123")
    member = User.create!(email: "share-links-policy-member@example.com", password: "password123")
    workspace = Workspace.create!(name: "Policy share", slug: "policy-share")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: workspace, user: member, role: :member)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Manager-only page")
    sign_in member

    post page_share_links_path(workspace_slug: workspace.slug, page_id: page.id)

    expect(response).to redirect_to(root_path)
    expect(ShareLink.count).to eq(0)
  end
end
