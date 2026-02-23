require "rails_helper"

RSpec.describe "Invitations", type: :request do
  include ActiveJob::TestHelper

  around do |example|
    perform_enqueued_jobs { example.run }
  end

  before do
    ActionMailer::Base.deliveries.clear
  end

  it "sends an invitation email when an owner invites a user" do
    owner = User.create!(email: "invite-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Research", slug: "research")
    Membership.create!(workspace: workspace, user: owner, role: :owner)

    sign_in owner

    expect do
      post workspace_invitations_path(workspace_slug: workspace.slug), params: { invitation: { email: "joiner@example.com", role: "guest" } }
    end.to change(Invitation, :count).by(1)

    expect(response).to redirect_to(workspace_path(workspace.slug))
    expect(ActionMailer::Base.deliveries.last.to).to include("joiner@example.com")
    expect(AuditEvent.recent_first.first.action).to eq("share")
  end

  it "creates membership when a valid invitation is accepted" do
    owner = User.create!(email: "owner2@example.com", password: "password123")
    invitee = User.create!(email: "invitee@example.com", password: "password123")
    workspace = Workspace.create!(name: "Ops", slug: "ops")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    invitation = Invitation.create!(workspace: workspace, invited_by: owner, email: invitee.email, role: :member, expires_at: 3.days.from_now)

    sign_in invitee

    expect do
      post accept_invitation_path(invitation.token)
    end.to change(Membership, :count).by(1)

    expect(response).to redirect_to(workspace_path(workspace.slug))
    expect(Membership.find_by!(workspace: workspace, user: invitee).role).to eq("member")
  end

  it "rejects expired invitations" do
    owner = User.create!(email: "owner3@example.com", password: "password123")
    invitee = User.create!(email: "expired-invitee@example.com", password: "password123")
    workspace = Workspace.create!(name: "Design", slug: "design")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    invitation = Invitation.create!(workspace: workspace, invited_by: owner, email: invitee.email, role: :guest, expires_at: 1.day.ago)

    sign_in invitee
    post accept_invitation_path(invitation.token)

    expect(response).to redirect_to(invitation_path(invitation.token))
    expect(Membership.where(workspace: workspace, user: invitee)).to be_empty
  end
end
