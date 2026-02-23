require "rails_helper"

RSpec.describe PageLinkPolicy::Scope do
  it "filters out page links to pages hidden by page-level permissions" do
    owner = User.create!(email: "link-policy-owner@example.com", password: "password123")
    member = User.create!(email: "link-policy-member@example.com", password: "password123")
    workspace = Workspace.create!(name: "Link Policy", slug: "link-policy")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: workspace, user: member, role: :member)
    source_page = Page.create!(workspace: workspace, created_by: owner, title: "Source")
    target_page = Page.create!(workspace: workspace, created_by: owner, title: "Private Target", permission_mode: :private_page)
    block = Block.create!(workspace: workspace, page: source_page, created_by: owner, block_type: "paragraph")
    link = PageLink.create!(workspace: workspace, source_page: source_page, target_page: target_page, source_block: block)

    owner_scope = described_class.new(owner, PageLink.all).resolve
    member_scope = described_class.new(member, PageLink.all).resolve

    expect(owner_scope).to include(link)
    expect(member_scope).not_to include(link)
  end
end
