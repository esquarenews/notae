require "rails_helper"

RSpec.describe Blocks::RestoreService do
  it "restores archived block to its original position by shifting active collisions" do
    owner = User.create!(email: "restore-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Restore", slug: "restore")
    page = Page.create!(workspace: workspace, created_by: owner, title: "Restore page")
    archived = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "paragraph", position: 1024)
    active = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "paragraph", position: 2048)

    Blocks::ArchiveService.call(block: archived)
    active.update!(position: 1024)

    described_class.call(block: archived.reload)

    expect(archived.reload.archived_at).to be_nil
    expect(archived.position).to eq(1024)
    expect(active.reload.position).to be > archived.position
  end
end
