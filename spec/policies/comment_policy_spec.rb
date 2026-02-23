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
end
