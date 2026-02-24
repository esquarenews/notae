require "rails_helper"

RSpec.describe PageTemplatePolicy do
  it "allows owner/member and blocks guest for template creation and instantiation" do
    workspace = Workspace.create!(name: "Template policy", slug: "template-policy")
    owner = User.create!(email: "template-policy-owner@example.com", password: "password123")
    member = User.create!(email: "template-policy-member@example.com", password: "password123")
    guest = User.create!(email: "template-policy-guest@example.com", password: "password123")

    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: workspace, user: member, role: :member)
    Membership.create!(workspace: workspace, user: guest, role: :guest)

    page = Page.create!(workspace: workspace, created_by: owner, title: "Source")
    template = PageTemplate.new(
      workspace: workspace,
      page: page,
      created_by: owner,
      name: "Source Template",
      snapshot_json: { "page_title" => "Source", "blocks" => [] }
    )

    expect(described_class.new(owner, template).create?).to eq(true)
    expect(described_class.new(member, template).create?).to eq(true)
    expect(described_class.new(guest, template).create?).to eq(false)

    expect(described_class.new(owner, template).instantiate?).to eq(true)
    expect(described_class.new(member, template).instantiate?).to eq(true)
    expect(described_class.new(guest, template).instantiate?).to eq(false)
  end
end
