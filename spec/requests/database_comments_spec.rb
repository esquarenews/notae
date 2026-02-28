require "rails_helper"

RSpec.describe "Database comments", type: :request do
  it "adds a comment to a grid from the topbar comments menu flow" do
    owner = User.create!(email: "database-comment-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Grid comments", slug: "grid-comments")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Status board")
    sign_in owner

    post database_comments_path(workspace_slug: workspace.slug, database_id: database.id, view_id: "table"),
         params: { comment: { body: "Please review this row." } }

    expect(response).to redirect_to(
      database_path(workspace_slug: workspace.slug, id: database.id, view_id: "table", anchor: "database-comments-menu")
    )
    comment = Comment.find_by!(commentable: database)
    expect(comment.body).to eq("Please review this row.")
    expect(comment.author).to eq(owner)
  end

  it "resolves and reopens a grid comment" do
    owner = User.create!(email: "database-comment-resolve-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Grid comments resolve", slug: "grid-comments-resolve")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Resolve board")
    comment = Comment.create!(
      workspace: workspace,
      commentable: database,
      author: owner,
      body: "Needs cleanup"
    )
    sign_in owner

    patch resolve_database_comment_path(workspace_slug: workspace.slug, database_id: database.id, id: comment.id)

    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id, anchor: "database-comments-menu"))
    expect(comment.reload).to be_resolved

    patch unresolve_database_comment_path(workspace_slug: workspace.slug, database_id: database.id, id: comment.id)

    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id, anchor: "database-comments-menu"))
    expect(comment.reload).not_to be_resolved
  end

  it "renders topbar comments/options and removes duplicate grid toolbar icons" do
    owner = User.create!(email: "database-comment-toolbar-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Grid comments toolbar", slug: "grid-comments-toolbar")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Toolbar board")
    sign_in owner

    get database_path(workspace_slug: workspace.slug, id: database.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('id="database-comments-menu"')
    expect(response.body).to include('id="database-options-menu"')
    expect(response.body).not_to include('title="Quick menu"')
    expect(response.body).not_to include('title="Sort"')
    expect(response.body).not_to include('title="Search"')
  end
end
