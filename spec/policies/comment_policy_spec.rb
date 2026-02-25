require "rails_helper"

RSpec.describe CommentPolicy do
  it "enforces page visibility permissions for comments" do
    owner = User.create!(email: "comment-pol-owner@example.com", password: "password123")
    member = User.create!(email: "comment-pol-member@example.com", password: "password123")
    workspace = Workspace.create!(name: "Comment Policy", slug: "comment-policy")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: workspace, user: member, role: :member)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Private Page", permission_mode: :private_page)
    comment = Comment.new(workspace: workspace, commentable: page, author: owner, body: "Hello")

    expect(described_class.new(owner, comment).create?).to be(true)
    expect(described_class.new(member, comment).create?).to be(false)
  end

  it "policy scope returns comments for pages visible to the user" do
    owner = User.create!(email: "comment-pol-scope-owner@example.com", password: "password123")
    member = User.create!(email: "comment-pol-scope-member@example.com", password: "password123")
    outsider = User.create!(email: "comment-pol-scope-outsider@example.com", password: "password123")

    workspace = Workspace.create!(name: "Comment Scope", slug: "comment-scope")
    other_workspace = Workspace.create!(name: "Comment Scope Other", slug: "comment-scope-other")

    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: workspace, user: member, role: :member)
    Membership.create!(workspace: other_workspace, user: outsider, role: :owner)

    visible_page = Page.create!(workspace: workspace, created_by: owner, title: "Visible")
    hidden_page = Page.create!(workspace: workspace, created_by: owner, title: "Hidden", permission_mode: :private_page)
    other_page = Page.create!(workspace: other_workspace, created_by: outsider, title: "Other")

    visible_comment = Comment.create!(workspace: workspace, commentable: visible_page, author: owner, body: "Visible comment")
    Comment.create!(workspace: workspace, commentable: hidden_page, author: owner, body: "Hidden comment")
    Comment.create!(workspace: other_workspace, commentable: other_page, author: outsider, body: "Other comment")

    resolved_ids = described_class::Scope.new(member, Comment).resolve.pluck(:id)

    expect(resolved_ids).to include(visible_comment.id)
    expect(resolved_ids.length).to eq(1)
  end
end
