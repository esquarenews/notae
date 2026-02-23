require "rails_helper"

RSpec.describe Blocks::ReorderService do
  it "reorders blocks without duplicating positions" do
    owner = User.create!(email: "reorder-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Service", slug: "service")
    page = Page.create!(workspace: workspace, created_by: owner, title: "Service Page")
    first = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "paragraph")
    second = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "paragraph")
    third = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "paragraph")

    described_class.call(block: third, target_parent_id: nil, target_index: 1)

    positions = page.blocks.active.roots.ordered.pluck(:position)
    ordered_ids = page.blocks.active.roots.ordered.pluck(:id)

    expect(ordered_ids).to eq([ first.id, third.id, second.id ])
    expect(positions.uniq.length).to eq(positions.length)
  end
end
