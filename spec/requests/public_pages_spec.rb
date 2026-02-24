require "rails_helper"

RSpec.describe "Public pages", type: :request do
  it "renders a shared page in read-only mode and logs access" do
    owner = User.create!(email: "public-page-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Public workspace", slug: "public-workspace")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Shared document")
    Block.create!(
      workspace: workspace,
      page: page,
      created_by: owner,
      block_type: "paragraph",
      content_json: { "type" => "doc", "content" => [ { "type" => "paragraph", "content" => [ { "type" => "text", "text" => "Hello public world" } ] } ] }
    )
    share_link = ShareLink.create!(workspace: workspace, page: page, created_by: owner)

    get public_share_path(token: share_link.token)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Shared document")
    expect(response.body).to include("Hello public world")
    expect(response.body).not_to include("Add block")
    view_event = ShareLinkView.recent_first.first
    expect(view_event.share_link_id).to eq(share_link.id)
    expect(view_event.ip_address).to be_present
    expect(view_event.viewed_at).to be_present
    expect(share_link.reload.last_viewed_at).to be_present
  end

  it "returns 404 for invalid, expired, or revoked tokens" do
    owner = User.create!(email: "public-page-invalid-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Invalid share workspace", slug: "invalid-share-workspace")
    page = Page.create!(workspace: workspace, created_by: owner, title: "Invalid token page")
    expired = ShareLink.create!(workspace: workspace, page: page, created_by: owner, expires_at: 1.minute.ago)
    revoked = ShareLink.create!(workspace: workspace, page: page, created_by: owner)
    revoked.revoke!

    get public_share_path(token: "missing-token")
    expect(response).to have_http_status(:not_found)

    get public_share_path(token: expired.token)
    expect(response).to have_http_status(:not_found)

    get public_share_path(token: revoked.token)
    expect(response).to have_http_status(:not_found)
  end
end
