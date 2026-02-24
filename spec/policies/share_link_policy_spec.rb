require "rails_helper"

RSpec.describe ShareLinkPolicy do
  describe "#create?" do
    it "allows owners and page creators, denies regular members" do
      owner = User.create!(email: "share-policy-owner@example.com", password: "password123")
      creator = User.create!(email: "share-policy-creator@example.com", password: "password123")
      member = User.create!(email: "share-policy-member@example.com", password: "password123")
      workspace = Workspace.create!(name: "Share policy", slug: "share-policy")
      Membership.create!(workspace: workspace, user: owner, role: :owner)
      Membership.create!(workspace: workspace, user: creator, role: :member)
      Membership.create!(workspace: workspace, user: member, role: :member)
      page = Page.create!(workspace: workspace, created_by: creator, title: "Creator page")
      share_link = ShareLink.new(page: page, workspace: workspace, created_by: creator)

      expect(described_class.new(owner, share_link).create?).to eq(true)
      expect(described_class.new(creator, share_link).create?).to eq(true)
      expect(described_class.new(member, share_link).create?).to eq(false)
    end
  end

  describe described_class::Scope do
    it "only includes links the user can manage" do
      owner = User.create!(email: "share-policy-scope-owner@example.com", password: "password123")
      member = User.create!(email: "share-policy-scope-member@example.com", password: "password123")
      workspace = Workspace.create!(name: "Share policy scope", slug: "share-policy-scope")
      Membership.create!(workspace: workspace, user: owner, role: :owner)
      Membership.create!(workspace: workspace, user: member, role: :member)
      owner_page = Page.create!(workspace: workspace, created_by: owner, title: "Owner page")
      owner_link = ShareLink.create!(workspace: workspace, page: owner_page, created_by: owner)

      scope_for_owner = described_class.new(owner, ShareLink.all).resolve
      scope_for_member = described_class.new(member, ShareLink.all).resolve

      expect(scope_for_owner).to include(owner_link)
      expect(scope_for_member).to be_empty
    end
  end
end
