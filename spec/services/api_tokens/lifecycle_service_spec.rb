require "rails_helper"

RSpec.describe ApiTokens::LifecycleService do
  it "issues a scoped token and records an audit event" do
    user = User.create!(email: "api-token-service-issue@example.com", password: "password123")
    workspace = Workspace.create!(name: "API token lifecycle", slug: "api-token-lifecycle")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    token = described_class.new(user: user, workspace: workspace).issue!(
      name: "Codex MCP",
      scopes_json: [ ApiToken::SCOPE_PAGES_READ, ApiToken::SCOPE_NOTIFICATIONS_WRITE ],
      expires_at: 30.days.from_now,
      metadata: { source: "spec" }
    )

    expect(token).to be_persisted
    expect(token.scopes).to contain_exactly(ApiToken::SCOPE_PAGES_READ, ApiToken::SCOPE_NOTIFICATIONS_WRITE)
    expect(token.expires_at).to be_present

    audit_event = ApiTokenAuditEvent.order(:created_at).last
    expect(audit_event).to have_attributes(
      api_token_id: token.id,
      user_id: user.id,
      workspace_id: workspace.id,
      event_type: "issued"
    )
    expect(audit_event.metadata_json).to include("source" => "spec")
  end

  it "revokes an active token and records an audit event" do
    user = User.create!(email: "api-token-service-revoke@example.com", password: "password123")
    workspace = Workspace.create!(name: "API token revoke", slug: "api-token-revoke")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    token = user.api_tokens.create!(name: "Codex MCP")

    described_class.new(user: user, workspace: workspace).revoke!(token, metadata: { source: "spec" })

    expect(token.reload.revoked_at).to be_present

    audit_event = ApiTokenAuditEvent.order(:created_at).last
    expect(audit_event).to have_attributes(
      api_token_id: token.id,
      event_type: "revoked"
    )
    expect(audit_event.metadata_json).to include("source" => "spec")
  end

  it "rotates a token by issuing a replacement and revoking the original" do
    user = User.create!(email: "api-token-service-rotate@example.com", password: "password123")
    workspace = Workspace.create!(name: "API token rotate", slug: "api-token-rotate")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    token = user.api_tokens.create!(
      name: "Codex MCP",
      scopes_json: [ ApiToken::SCOPE_PAGES_READ ],
      expires_at: 14.days.from_now
    )

    replacement = described_class.new(user: user, workspace: workspace).rotate!(token, metadata: { source: "spec" })

    expect(replacement).to be_persisted
    expect(replacement.id).not_to eq(token.id)
    expect(replacement.name).to eq(token.name)
    expect(replacement.scopes).to eq(token.scopes)
    expect(replacement.expires_at.to_i).to eq(token.expires_at.to_i)
    expect(token.reload.revoked_at).to be_present

    events = ApiTokenAuditEvent.where(user: user).order(:created_at)
    expect(events.pluck(:event_type)).to include("issued", "revoked")

    issued_event = events.detect { |event| event.api_token_id == replacement.id && event.event_type == "issued" }
    revoked_event = events.detect { |event| event.api_token_id == token.id && event.event_type == "revoked" }
    expect(issued_event.metadata_json).to include("rotated_from_api_token_id" => token.id, "source" => "spec")
    expect(revoked_event.metadata_json).to include("rotated_to_api_token_id" => replacement.id, "source" => "spec")
  end
end
