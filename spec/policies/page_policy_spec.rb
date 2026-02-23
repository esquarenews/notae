require "rails_helper"

RSpec.describe PagePolicy do
  it "allows owner/admin/member to create and blocks guest from creating pages" do
    workspace = Workspace.create!(name: "Page Policy", slug: "page-policy")
    owner = User.create!(email: "page-pol-owner@example.com", password: "password123")
    admin = User.create!(email: "page-pol-admin@example.com", password: "password123")
    member = User.create!(email: "page-pol-member@example.com", password: "password123")
    guest = User.create!(email: "page-pol-guest@example.com", password: "password123")

    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: workspace, user: admin, role: :admin)
    Membership.create!(workspace: workspace, user: member, role: :member)
    Membership.create!(workspace: workspace, user: guest, role: :guest)

    new_page = Page.new(workspace: workspace, created_by: owner, title: "X")

    expect(described_class.new(owner, new_page).create?).to be(true)
    expect(described_class.new(admin, new_page).create?).to be(true)
    expect(described_class.new(member, new_page).create?).to be(true)
    expect(described_class.new(guest, new_page).create?).to be(false)
  end

  it "enforces private and specific user visibility modes" do
    workspace = Workspace.create!(name: "Visibility Policy", slug: "visibility-policy")
    owner = User.create!(email: "vis-owner@example.com", password: "password123")
    member = User.create!(email: "vis-member@example.com", password: "password123")
    other = User.create!(email: "vis-other@example.com", password: "password123")

    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: workspace, user: member, role: :member)
    Membership.create!(workspace: workspace, user: other, role: :member)

    private_page = Page.create!(workspace: workspace, created_by: owner, title: "Private", permission_mode: :private_page)
    specific_page = Page.create!(workspace: workspace, created_by: owner, title: "Specific", permission_mode: :specific_users)
    PageShare.create!(page: specific_page, user: member, created_by: owner)

    expect(described_class.new(member, private_page).show?).to be(false)
    expect(described_class.new(owner, private_page).show?).to be(true)
    expect(described_class.new(member, specific_page).show?).to be(true)
    expect(described_class.new(other, specific_page).show?).to be(false)
  end
end
