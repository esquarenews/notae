require "rails_helper"

RSpec.describe PageChannel, type: :channel do
  it "tracks join and leave presence for authorized members" do
    owner = User.create!(email: "channel-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Realtime", slug: "realtime")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Realtime page")

    stub_connection current_user: owner

    subscribe(workspace_slug: workspace.slug, page_id: page.id)

    expect(subscription).to be_confirmed
    expect(PagePresence.where(page: page, user: owner).count).to eq(1)

    unsubscribe

    expect(PagePresence.where(page: page, user: owner)).to be_empty
  end

  it "rejects users without page access" do
    owner = User.create!(email: "channel-page-owner@example.com", password: "password123")
    intruder = User.create!(email: "channel-page-intruder@example.com", password: "password123")
    workspace = Workspace.create!(name: "Realtime private", slug: "realtime-private")
    other_workspace = Workspace.create!(name: "Other realtime", slug: "other-realtime")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: other_workspace, user: intruder, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Realtime private page")

    stub_connection current_user: intruder

    subscribe(workspace_slug: workspace.slug, page_id: page.id)

    expect(subscription).to be_rejected
  end

  it "stores and clears block editing presence" do
    owner = User.create!(email: "channel-edit-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Realtime editing", slug: "realtime-editing")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Realtime editing page")
    block = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "paragraph")

    stub_connection current_user: owner
    subscribe(workspace_slug: workspace.slug, page_id: page.id)

    perform :editing_start, { block_id: block.id }
    presence = PagePresence.where(page: page, user: owner).order(created_at: :desc).first
    expect(presence.editing_block_id).to eq(block.id)

    perform :editing_stop, { block_id: block.id }
    expect(presence.reload.editing_block_id).to be_nil
  end
end
