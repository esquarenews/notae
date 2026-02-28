require "rails_helper"

RSpec.describe ShareLink, type: :model do
  it "generates a URL-safe token with at least 32 bytes of entropy" do
    owner = User.create!(email: "share-link-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Share", slug: "share")
    page = Page.create!(workspace: workspace, created_by: owner, title: "Public page")

    share_link = described_class.create!(page: page, created_by: owner)
    decoded = Base64.urlsafe_decode64(share_link.token + ("=" * ((4 - (share_link.token.length % 4)) % 4)))

    expect(share_link.workspace_id).to eq(workspace.id)
    expect(decoded.bytesize).to be >= 32
  end

  it "can be revoked and becomes inactive immediately" do
    owner = User.create!(email: "share-link-revoke-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Share revoke", slug: "share-revoke")
    page = Page.create!(workspace: workspace, created_by: owner, title: "Public page")
    share_link = described_class.create!(page: page, created_by: owner)

    expect(share_link).to be_active

    share_link.revoke!

    expect(share_link).not_to be_active
    expect(share_link.revoked_at).to be_present
  end

  it "encrypts public share token at rest" do
    owner = User.create!(email: "share-link-encrypted-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Share encrypted", slug: "share-encrypted")
    page = Page.create!(workspace: workspace, created_by: owner, title: "Public page")
    share_link = described_class.create!(page: page, created_by: owner)
    plaintext = share_link.token

    share_link.reload

    expect(share_link.attributes_before_type_cast["token"]).not_to eq(plaintext)
    expect(share_link.token).to eq(plaintext)
  end
end
