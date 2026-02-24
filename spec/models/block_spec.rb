require "rails_helper"

RSpec.describe Block, type: :model do
  it "persists ProseMirror JSON content" do
    owner = User.create!(email: "block-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Editor", slug: "editor")
    page = Page.create!(workspace: workspace, created_by: owner, title: "Spec")
    content = { "type" => "doc", "content" => [ { "type" => "paragraph", "content" => [ { "type" => "text", "text" => "Hello" } ] } ] }

    block = described_class.create!(workspace: workspace, page: page, created_by: owner, content_json: content, block_type: "paragraph")

    expect(block.reload.content_json).to eq(content)
  end

  it "supports nested blocks" do
    owner = User.create!(email: "nested-block-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Nested", slug: "nested")
    page = Page.create!(workspace: workspace, created_by: owner, title: "Nested page")
    parent = described_class.create!(workspace: workspace, page: page, created_by: owner, block_type: "paragraph")
    child = described_class.create!(workspace: workspace, page: page, parent_block: parent, created_by: owner, block_type: "paragraph")

    expect(parent.child_blocks).to include(child)
  end

  it "allows allowlisted embed domains" do
    owner = User.create!(email: "embed-valid-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Embeds valid", slug: "embeds-valid")
    page = Page.create!(workspace: workspace, created_by: owner, title: "Embeds")
    block = described_class.new(
      workspace: workspace,
      page: page,
      created_by: owner,
      block_type: "embed",
      embed_url: "https://www.youtube.com/embed/dQw4w9WgXcQ"
    )

    expect(block).to be_valid
  end

  it "rejects non-allowlisted embed domains" do
    owner = User.create!(email: "embed-invalid-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Embeds invalid", slug: "embeds-invalid")
    page = Page.create!(workspace: workspace, created_by: owner, title: "Embeds")
    block = described_class.new(
      workspace: workspace,
      page: page,
      created_by: owner,
      block_type: "embed",
      embed_url: "https://example.com/embed/video"
    )

    expect(block).not_to be_valid
    expect(block.errors[:embed_url]).to include("is not in the allowlist")
  end

  it "uses top-level page links sync service from the callback helper" do
    owner = User.create!(email: "page-links-constant-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Link scope", slug: "link-scope")
    page = Page.create!(workspace: workspace, created_by: owner, title: "Links")
    block = described_class.new(workspace: workspace, page: page, created_by: owner, block_type: "paragraph")
    stub_const("Block::PageLinks", Module.new)
    allow(::PageLinks::SyncFromBlockService).to receive(:call)

    block.send(:sync_page_links)

    expect(::PageLinks::SyncFromBlockService).to have_received(:call).with(block: block)
  end

  it "loads the page link sync service with an absolute path when constant is missing" do
    owner = User.create!(email: "page-links-load-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Link load scope", slug: "link-load-scope")
    page = Page.create!(workspace: workspace, created_by: owner, title: "Links")
    block = described_class.new(workspace: workspace, page: page, created_by: owner, block_type: "paragraph")
    hide_const("PageLinks")

    expect { block.send(:sync_page_links) }.not_to raise_error
  end
end
