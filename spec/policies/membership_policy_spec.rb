require "rails_helper"

RSpec.describe MembershipPolicy do
  it "allows owners and selected admins to update roles based on target role" do
    workspace = Workspace.create!(name: "Membership Policy", slug: "membership-policy")
    owner = User.create!(email: "mem-pol-owner@example.com", password: "password123")
    admin = User.create!(email: "mem-pol-admin@example.com", password: "password123")
    member = User.create!(email: "mem-pol-member@example.com", password: "password123")
    owner_target = User.create!(email: "mem-pol-owner-target@example.com", password: "password123")
    member_target = User.create!(email: "mem-pol-member-target@example.com", password: "password123")

    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: workspace, user: admin, role: :admin)
    Membership.create!(workspace: workspace, user: member, role: :member)
    owner_membership = Membership.create!(workspace: workspace, user: owner_target, role: :owner)
    member_membership = Membership.create!(workspace: workspace, user: member_target, role: :member)

    expect(described_class.new(owner, member_membership).update?).to be(true)
    expect(described_class.new(owner, owner_membership).update?).to be(false)
    expect(described_class.new(admin, member_membership).update?).to be(true)
    expect(described_class.new(admin, owner_membership).update?).to be(false)
    expect(described_class.new(member, member_membership).update?).to be(false)
  end
end
