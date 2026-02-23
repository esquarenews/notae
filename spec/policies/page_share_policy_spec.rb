require "rails_helper"

RSpec.describe PageSharePolicy do
  it "allows page owner to manage page shares" do
    owner = User.create!(email: "share-owner@example.com", password: "password123")
    member = User.create!(email: "share-member@example.com", password: "password123")
    workspace = Workspace.create!(name: "Page Share", slug: "page-share")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: workspace, user: member, role: :member)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Shared", permission_mode: :specific_users)
    page_share = PageShare.new(page: page, user: member, created_by: owner)

    expect(described_class.new(owner, page_share).create?).to be(true)
  end
end
