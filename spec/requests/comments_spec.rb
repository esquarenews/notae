require "rails_helper"

RSpec.describe "Comments", type: :request do
  it "creates page comments and supports resolve/unresolve" do
    owner = User.create!(email: "comments-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Comments Workspace", slug: "comments-workspace")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Commented")

    sign_in owner
    expect do
      post page_comments_path(workspace_slug: workspace.slug, page_id: page.id), params: { comment: { body: "Needs review" } }
    end.to change(Comment, :count).by(1)
    comment = Comment.last

    patch resolve_page_comment_path(workspace_slug: workspace.slug, page_id: page.id, id: comment.id)
    expect(comment.reload).to be_resolved

    patch unresolve_page_comment_path(workspace_slug: workspace.slug, page_id: page.id, id: comment.id)
    expect(comment.reload).not_to be_resolved
  end

  it "creates block comments with permission checks enforced" do
    owner = User.create!(email: "comments-owner-2@example.com", password: "password123")
    outsider = User.create!(email: "comments-outsider@example.com", password: "password123")
    workspace = Workspace.create!(name: "Comments Workspace 2", slug: "comments-workspace-2")
    other_workspace = Workspace.create!(name: "Comments Other", slug: "comments-other")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: other_workspace, user: outsider, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Commented Block")
    block = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "paragraph")

    sign_in outsider
    post page_block_comments_path(workspace_slug: workspace.slug, page_id: page.id, block_id: block.id), params: { comment: { body: "No access" } }

    expect(response).to have_http_status(:not_found)
  end
end
