require "rails_helper"

RSpec.describe "Blocks", type: :request do
  it "updates block JSON without redirect for in-place editor persistence" do
    owner = User.create!(email: "blocks-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Blocks", slug: "blocks")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Editor")
    block = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "paragraph")
    sign_in owner

    patch page_block_path(workspace_slug: workspace.slug, page_id: page.id, id: block.id),
          params: {
            block: {
              block_type: "heading_1",
              content_json: {
                type: "doc",
                content: [ { type: "heading", attrs: { level: 1 }, content: [ { type: "text", text: "Heading" } ] } ]
              }
            }
          },
          as: :json

    expect(response).to have_http_status(:ok)
    expect(response).not_to be_redirect
    expect(block.reload.block_type).to eq("heading_1")
  end

  it "reorders blocks with a drag-drop style request" do
    owner = User.create!(email: "blocks-reorder-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Reorder", slug: "reorder")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Reorder page")
    first = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "paragraph")
    second = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "paragraph")
    sign_in owner

    patch reorder_page_block_path(workspace_slug: workspace.slug, page_id: page.id, id: second.id),
          params: { target_parent_id: nil, target_index: 0 },
          as: :json

    expect(response).to have_http_status(:ok)
    expect(page.blocks.active.roots.ordered.first.id).to eq(second.id)
  end

  it "archives and restores blocks while preserving original position priority" do
    owner = User.create!(email: "blocks-archive-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Archive blocks", slug: "archive-blocks")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Archive page")
    block = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "paragraph", position: 1024)
    sign_in owner

    patch archive_page_block_path(workspace_slug: workspace.slug, page_id: page.id, id: block.id)
    expect(block.reload.archived_at).to be_present
    expect(AuditEvent.recent_first.first.action).to eq("delete")

    patch restore_page_block_path(workspace_slug: workspace.slug, page_id: page.id, id: block.id)
    expect(block.reload.archived_at).to be_nil
    expect(block.position).to eq(1024)
  end

  it "blocks cross-workspace block updates" do
    owner = User.create!(email: "block-owner-cross@example.com", password: "password123")
    intruder = User.create!(email: "block-intruder-cross@example.com", password: "password123")
    workspace = Workspace.create!(name: "Block Cross", slug: "block-cross")
    other_workspace = Workspace.create!(name: "Other Block", slug: "other-block")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: other_workspace, user: intruder, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Target")
    block = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "paragraph")

    sign_in intruder
    patch page_block_path(workspace_slug: workspace.slug, page_id: page.id, id: block.id),
          params: { block: { block_type: "heading_1" } },
          as: :json

    expect(response).to have_http_status(:not_found)
  end

  it "uploads and downloads files for workspace members" do
    owner = User.create!(email: "blocks-file-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "File blocks", slug: "file-blocks")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Files")
    block = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "file")
    sign_in owner

    Tempfile.create([ "block-upload", ".txt" ]) do |file|
      file.write("file content")
      file.rewind
      uploaded_file = Rack::Test::UploadedFile.new(file.path, "text/plain")

      patch attach_page_block_path(workspace_slug: workspace.slug, page_id: page.id, id: block.id),
            params: { block: { file: uploaded_file } }
    end

    expect(response).to redirect_to(page_path(workspace_slug: workspace.slug, id: page.id))
    expect(block.reload.asset).to be_attached

    get download_page_block_path(workspace_slug: workspace.slug, page_id: page.id, id: block.id)

    expect(response).to have_http_status(:ok)
    expect(response.headers["Content-Disposition"]).to include("attachment")
    expect(response.body).to eq("file content")
  end

  it "blocks cross-workspace file upload and download access" do
    owner = User.create!(email: "blocks-file-access-owner@example.com", password: "password123")
    intruder = User.create!(email: "blocks-file-access-intruder@example.com", password: "password123")
    workspace = Workspace.create!(name: "File access", slug: "file-access")
    other_workspace = Workspace.create!(name: "Other files", slug: "other-files")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: other_workspace, user: intruder, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Protected file")
    block = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "file")

    Tempfile.create([ "block-upload", ".txt" ]) do |file|
      file.write("secret")
      file.rewind
      block.asset.attach(io: file, filename: "secret.txt", content_type: "text/plain")
    end

    sign_in intruder
    original_blob_id = block.reload.asset.blob.id

    Tempfile.create([ "intruder-upload", ".txt" ]) do |file|
      file.write("intrusion")
      file.rewind
      uploaded_file = Rack::Test::UploadedFile.new(file.path, "text/plain")

      patch attach_page_block_path(workspace_slug: workspace.slug, page_id: page.id, id: block.id),
            params: { block: { file: uploaded_file } }
    end

    expect([ 302, 404 ]).to include(response.status)
    expect(block.reload.asset.blob.id).to eq(original_blob_id)

    get download_page_block_path(workspace_slug: workspace.slug, page_id: page.id, id: block.id)

    expect([ 302, 404 ]).to include(response.status)
  end

  it "rejects embed URLs that are outside the allowlist" do
    owner = User.create!(email: "blocks-embed-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Embeds", slug: "embeds")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Embeds page")
    block = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "embed")
    sign_in owner

    patch page_block_path(workspace_slug: workspace.slug, page_id: page.id, id: block.id),
          params: { block: { embed_url: "https://example.com/not-allowed" } }

    expect(response).to redirect_to(page_path(workspace_slug: workspace.slug, id: page.id))
    expect(block.reload.embed_url).to be_nil
  end
end
