require "rails_helper"

RSpec.describe "Page imports", type: :request do
  def uploaded_file(name, content, content_type)
    file = Tempfile.new([ File.basename(name, ".*"), File.extname(name) ])
    file.binmode
    file.write(content)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, content_type, original_filename: name)
  end

  def paragraph_content(text)
    {
      "type" => "doc",
      "content" => [
        {
          "type" => "paragraph",
          "content" => [
            { "type" => "text", "text" => text }
          ]
        }
      ]
    }
  end

  it "imports document content directly after the selected block" do
    owner = User.create!(email: "page-import-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Page import", slug: "page-import")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Imported note")
    first_block = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "paragraph", content_json: paragraph_content("First"))
    second_block = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "paragraph", content_json: paragraph_content("Second"))
    sign_in owner

    markdown = uploaded_file("outline.md", "# Imported heading\n\nImported body", "text/markdown")

    expect do
      post import_page_path(workspace_slug: workspace.slug, id: page.id),
           params: {
             return_to: page_path(workspace_slug: workspace.slug, id: page.id),
             import: {
               insert_after_id: first_block.id,
               files: [ markdown ]
             }
           }
    end.to change(Block, :count).by(2)

    expect(response).to redirect_to(page_path(workspace_slug: workspace.slug, id: page.id))
    expect(flash[:notice]).to include("Imported 2 blocks.")

    ordered_ids = page.blocks.active.roots.ordered.pluck(:id)
    imported_blocks = page.blocks.active.where.not(id: [ first_block.id, second_block.id ]).ordered.to_a

    expect(ordered_ids).to eq([ first_block.id, imported_blocks[0].id, imported_blocks[1].id, second_block.id ])
    expect(imported_blocks.map(&:block_type)).to eq([ "heading_1", "paragraph" ])
    expect(imported_blocks.last.search_text).to include("Imported body")
  end

  it "imports media directly after the selected block as a media block" do
    owner = User.create!(email: "page-import-media-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Page import media", slug: "page-import-media")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Media note")
    first_block = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "paragraph", content_json: paragraph_content("Anchor"))
    second_block = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "paragraph", content_json: paragraph_content("Later"))
    sign_in owner

    image = uploaded_file("photo.png", "fake-png-data", "image/png")

    expect do
      post import_page_path(workspace_slug: workspace.slug, id: page.id),
           params: {
             return_to: page_path(workspace_slug: workspace.slug, id: page.id),
             import: {
               insert_after_id: first_block.id,
               files: [ image ]
             }
           }
    end.to change(Block, :count).by(1)

    imported_block = page.blocks.active.where.not(id: [ first_block.id, second_block.id ]).first
    ordered_ids = page.blocks.active.roots.ordered.pluck(:id)

    expect(response).to redirect_to(page_path(workspace_slug: workspace.slug, id: page.id))
    expect(imported_block.block_type).to eq("image")
    expect(imported_block.asset).to be_attached
    expect(ordered_ids).to eq([ first_block.id, imported_block.id, second_block.id ])
  end

  it "keeps multi-file imports in the order they were uploaded after the selected block" do
    owner = User.create!(email: "page-import-multi-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Page import multi", slug: "page-import-multi")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Multi import note")
    first_block = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "paragraph", content_json: paragraph_content("First"))
    second_block = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "paragraph", content_json: paragraph_content("Second"))
    sign_in owner

    first_markdown = uploaded_file("one.md", "First imported paragraph", "text/markdown")
    second_markdown = uploaded_file("two.md", "Second imported paragraph", "text/markdown")

    post import_page_path(workspace_slug: workspace.slug, id: page.id),
         params: {
           return_to: page_path(workspace_slug: workspace.slug, id: page.id),
           import: {
             insert_after_id: first_block.id,
             files: [ first_markdown, second_markdown ]
           }
         }

    expect(response).to redirect_to(page_path(workspace_slug: workspace.slug, id: page.id))

    imported_blocks = page.blocks.active.where.not(id: [ first_block.id, second_block.id ]).ordered.to_a
    ordered_ids = page.blocks.active.roots.ordered.pluck(:id)

    expect(ordered_ids).to eq([ first_block.id, imported_blocks[0].id, imported_blocks[1].id, second_block.id ])
    expect(imported_blocks.map(&:search_text)).to eq([ "First imported paragraph", "Second imported paragraph" ])
  end

  it "keeps csv imports on the workspace import flow" do
    owner = User.create!(email: "page-import-csv-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Page import csv", slug: "page-import-csv")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "CSV note")
    Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "paragraph", content_json: paragraph_content("Anchor"))
    sign_in owner

    csv = uploaded_file("table.csv", "name,value\nalpha,1\n", "text/csv")

    expect do
      post import_page_path(workspace_slug: workspace.slug, id: page.id),
           params: {
             return_to: page_path(workspace_slug: workspace.slug, id: page.id),
             import: { files: [ csv ] }
           }
    end.not_to change(Block, :count)

    expect(response).to redirect_to(page_path(workspace_slug: workspace.slug, id: page.id))
    expect(flash[:alert]).to include("Use Settings → Import for CSV or ZIP imports.")
  end
end
