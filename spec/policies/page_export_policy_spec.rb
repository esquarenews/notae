require "rails_helper"

RSpec.describe PageExportPolicy do
  it "follows page visibility rules for creating and downloading exports" do
    workspace = Workspace.create!(name: "Page export policy", slug: "page-export-policy")
    owner = User.create!(email: "page-export-pol-owner@example.com", password: "password123")
    member = User.create!(email: "page-export-pol-member@example.com", password: "password123")
    outsider = User.create!(email: "page-export-pol-outsider@example.com", password: "password123")

    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: workspace, user: member, role: :member)

    shared_page = Page.create!(workspace: workspace, created_by: owner, title: "Shared")
    private_page = Page.create!(workspace: workspace, created_by: owner, title: "Private", permission_mode: :private_page)

    shared_export = PageExport.new(workspace: workspace, page: shared_page, requested_by: owner)
    private_export = PageExport.new(workspace: workspace, page: private_page, requested_by: owner)

    expect(described_class.new(owner, shared_export).download?).to eq(true)
    expect(described_class.new(member, shared_export).download?).to eq(true)
    expect(described_class.new(member, private_export).download?).to eq(false)
    expect(described_class.new(outsider, shared_export).download?).to eq(false)
  end
end
