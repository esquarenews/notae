require "rails_helper"

RSpec.describe InvitationPolicy do
  it "allows only owner/admin to create invitations" do
    workspace = Workspace.create!(name: "Inv Policy", slug: "inv-policy")
    owner = User.create!(email: "inv-pol-owner@example.com", password: "password123")
    admin = User.create!(email: "inv-pol-admin@example.com", password: "password123")
    member = User.create!(email: "inv-pol-member@example.com", password: "password123")
    guest = User.create!(email: "inv-pol-guest@example.com", password: "password123")
    auditor = User.create!(email: "inv-pol-auditor@example.com", password: "password123")
    automation_agent = User.create!(email: "inv-pol-agent@example.com", password: "password123")

    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: workspace, user: admin, role: :admin)
    Membership.create!(workspace: workspace, user: member, role: :member)
    Membership.create!(workspace: workspace, user: guest, role: :guest)
    Membership.create!(workspace: workspace, user: auditor, role: :auditor)
    Membership.create!(workspace: workspace, user: automation_agent, role: :automation_agent)

    invitation = Invitation.new(workspace: workspace, invited_by: owner, email: "target@example.com", role: :guest, expires_at: 2.days.from_now)

    expect(described_class.new(owner, invitation).create?).to be(true)
    expect(described_class.new(admin, invitation).create?).to be(true)
    expect(described_class.new(member, invitation).create?).to be(false)
    expect(described_class.new(guest, invitation).create?).to be(false)
    expect(described_class.new(auditor, invitation).create?).to be(false)
    expect(described_class.new(automation_agent, invitation).create?).to be(false)
  end

  it "allows acceptance only for the invited email owner" do
    workspace = Workspace.create!(name: "Inv Accept", slug: "inv-accept")
    owner = User.create!(email: "inv-accept-owner@example.com", password: "password123")
    invitee = User.create!(email: "invitee-match@example.com", password: "password123")
    other = User.create!(email: "invitee-other@example.com", password: "password123")
    invitation = Invitation.create!(workspace: workspace, invited_by: owner, email: invitee.email, role: :member, expires_at: 2.days.from_now)

    expect(described_class.new(invitee, invitation).accept?).to be(true)
    expect(described_class.new(other, invitation).accept?).to be(false)
  end
end
