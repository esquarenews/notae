require "rails_helper"

RSpec.describe PageTemplates::InstantiateService, type: :service do
  it "duplicates a block tree with nested structure and attachments" do
    owner = User.create!(email: "template-service-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Template service", slug: "template-service")
    page = Page.create!(workspace: workspace, created_by: owner, title: "Original")

    parent_block = Block.create!(
      workspace: workspace,
      page: page,
      created_by: owner,
      block_type: "paragraph",
      content_json: { "type" => "doc", "content" => [ { "type" => "paragraph", "content" => [ { "type" => "text", "text" => "Parent block" } ] } ] }
    )
    Block.create!(
      workspace: workspace,
      page: page,
      parent_block: parent_block,
      created_by: owner,
      block_type: "paragraph",
      content_json: { "type" => "doc", "content" => [ { "type" => "paragraph", "content" => [ { "type" => "text", "text" => "Child block" } ] } ] }
    )
    file_block = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "file")
    Tempfile.create([ "template-service", ".txt" ]) do |file|
      file.write("template attachment")
      file.rewind
      file_block.asset.attach(io: file, filename: "template.txt", content_type: "text/plain")
    end

    template = PageTemplates::CreateFromPageService.call(page: page, created_by: owner, name: "Reusable")
    new_page = described_class.call(template: template, workspace: workspace, created_by: owner, title: "From template")

    expect(new_page.title).to eq("From template")
    expect(new_page.id).not_to eq(page.id)
    expect(new_page.blocks.active.count).to eq(page.blocks.active.count)

    new_parent = new_page.blocks.active.find_by(parent_block_id: nil, block_type: "paragraph")
    new_child = new_page.blocks.active.find_by(parent_block_id: new_parent.id, block_type: "paragraph")
    expect(new_parent).to be_present
    expect(new_child).to be_present

    new_file_block = new_page.blocks.active.find_by(block_type: "file")
    expect(new_file_block.asset).to be_attached
    expect(new_file_block.asset.blob_id).to eq(file_block.asset.blob_id)
  end
end
