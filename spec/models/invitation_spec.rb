require "rails_helper"

RSpec.describe Invitation, type: :model do
  it "accepts a pending invitation and creates membership with invited role" do
    owner = User.create!(email: "inv-owner@example.com", password: "password123")
    invitee = User.create!(email: "inv-invitee@example.com", password: "password123")
    workspace = Workspace.create!(name: "Security", slug: "security")
    invitation = described_class.create!(workspace: workspace, invited_by: owner, email: invitee.email, role: :guest, expires_at: 2.days.from_now)

    expect do
      invitation.accept!(invitee)
    end.to change(Membership, :count).by(1)

    expect(Membership.find_by!(workspace: workspace, user: invitee).role).to eq("guest")
    expect(invitation.reload).to be_accepted
  end

  it "marks expired invites as invalid for acceptance" do
    owner = User.create!(email: "inv-owner-2@example.com", password: "password123")
    invitee = User.create!(email: "inv-invitee-2@example.com", password: "password123")
    workspace = Workspace.create!(name: "Archive", slug: "archive")
    invitation = described_class.create!(workspace: workspace, invited_by: owner, email: invitee.email, role: :member, expires_at: 1.day.ago)

    expect(invitation).to be_expired
    expect { invitation.accept!(invitee) }.to raise_error(ActiveRecord::RecordInvalid)
  end
end
