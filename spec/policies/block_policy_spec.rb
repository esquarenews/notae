require "rails_helper"

RSpec.describe BlockPolicy do
  it "allows owner/admin/member to edit blocks and restricts guests" do
    workspace = Workspace.create!(name: "Block Policy", slug: "block-policy")
    page_owner = User.create!(email: "block-pol-page-owner@example.com", password: "password123")
    owner = User.create!(email: "block-pol-owner@example.com", password: "password123")
    admin = User.create!(email: "block-pol-admin@example.com", password: "password123")
    member = User.create!(email: "block-pol-member@example.com", password: "password123")
    guest = User.create!(email: "block-pol-guest@example.com", password: "password123")
    page = Page.create!(workspace: workspace, created_by: page_owner, title: "Page")
    block = Block.create!(workspace: workspace, page: page, created_by: page_owner, block_type: "paragraph")

    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: workspace, user: admin, role: :admin)
    Membership.create!(workspace: workspace, user: member, role: :member)
    Membership.create!(workspace: workspace, user: guest, role: :guest)

    expect(described_class.new(owner, block).update?).to be(true)
    expect(described_class.new(admin, block).update?).to be(true)
    expect(described_class.new(member, block).update?).to be(true)
    expect(described_class.new(guest, block).update?).to be(false)
  end

  it "respects page visibility overrides for block access" do
    workspace = Workspace.create!(name: "Block Visibility", slug: "block-visibility")
    page_owner = User.create!(email: "block-vis-owner@example.com", password: "password123")
    member = User.create!(email: "block-vis-member@example.com", password: "password123")
    page = Page.create!(workspace: workspace, created_by: page_owner, title: "Private Page", permission_mode: :private_page)
    block = Block.create!(workspace: workspace, page: page, created_by: page_owner, block_type: "paragraph")

    Membership.create!(workspace: workspace, user: page_owner, role: :owner)
    Membership.create!(workspace: workspace, user: member, role: :member)

    expect(described_class.new(page_owner, block).show?).to be(true)
    expect(described_class.new(member, block).show?).to be(false)
  end
end
