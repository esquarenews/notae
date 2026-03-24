require "rails_helper"

RSpec.describe "Blocks", type: :request do
  it "updates block JSON without redirect for in-place editor persistence" do
    owner = User.create!(email: "blocks-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Blocks", slug: "blocks")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Editor")
    block = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "paragraph")
    page.update_column(:updated_at, 2.hours.ago)
    previous_page_updated_at = page.reload.updated_at
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
    expect(page.reload.updated_at).to be > previous_page_updated_at
    payload = JSON.parse(response.body)
    expect(payload["page_updated_at"]).to be_present
  end

  it "preserves block color metadata when saving heading content" do
    owner = User.create!(email: "blocks-heading-color-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Heading colors", slug: "heading-colors")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Heading color page")
    block = Block.create!(
      workspace: workspace,
      page: page,
      created_by: owner,
      block_type: "heading_1",
      content_json: {
        "type" => "doc",
        "content" => [
          {
            "type" => "heading",
            "attrs" => { "level" => 1 },
            "content" => [ { "type" => "text", "text" => "Heading" } ]
          }
        ],
        "notae_color" => "blue"
      }
    )
    sign_in owner

    patch page_block_path(workspace_slug: workspace.slug, page_id: page.id, id: block.id),
          params: {
            block: {
              block_type: "heading_1",
              content_json: {
                type: "doc",
                content: [
                  {
                    type: "heading",
                    attrs: { level: 1 },
                    content: [ { type: "text", text: "Updated heading" } ]
                  }
                ]
              }
            }
          },
          as: :json

    expect(response).to have_http_status(:ok)
    expect(block.reload.content_json["notae_color"]).to eq("blue")
    expect(block.content_json.dig("content", 0, "content", 0, "text")).to eq("Updated heading")
  end

  it "preserves block highlight metadata when saving heading content" do
    owner = User.create!(email: "blocks-heading-highlight-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Heading highlights", slug: "heading-highlights")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Heading highlight page")
    block = Block.create!(
      workspace: workspace,
      page: page,
      created_by: owner,
      block_type: "heading_2",
      content_json: {
        "type" => "doc",
        "content" => [
          {
            "type" => "heading",
            "attrs" => { "level" => 2 },
            "content" => [ { "type" => "text", "text" => "Highlighted heading" } ]
          }
        ],
        "notae_highlight" => "mint"
      }
    )
    sign_in owner

    patch page_block_path(workspace_slug: workspace.slug, page_id: page.id, id: block.id),
          params: {
            block: {
              block_type: "heading_2",
              content_json: {
                type: "doc",
                content: [
                  {
                    type: "heading",
                    attrs: { level: 2 },
                    content: [ { type: "text", text: "Updated highlighted heading" } ]
                  }
                ]
              }
            }
          },
          as: :json

    expect(response).to have_http_status(:ok)
    expect(block.reload.content_json["notae_highlight"]).to eq("mint")
    expect(block.content_json.dig("content", 0, "content", 0, "text")).to eq("Updated highlighted heading")
  end

  it "formats @date mentions using the user date preference" do
    owner = User.create!(
      email: "blocks-date-mention-owner@example.com",
      password: "password123",
      date_format_preference: "month_day_year",
      auto_time_zone: false,
      time_zone: "UTC"
    )
    workspace = Workspace.create!(name: "Date mentions", slug: "date-mentions")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Date mention page")
    block = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "paragraph")
    sign_in owner

    today = Time.zone.today.strftime("%m/%d/%Y")
    patch page_block_path(workspace_slug: workspace.slug, page_id: page.id, id: block.id),
          params: {
            block: {
              block_type: "paragraph",
              content_json: {
                type: "doc",
                content: [ { type: "paragraph", content: [ { type: "text", text: "Review @date" } ] } ]
              }
            }
          },
          as: :json

    expect(response).to have_http_status(:ok)
    saved_text = block.reload.content_json.dig("content", 0, "content", 0, "text")
    expect(saved_text).to include("@#{today}")
  end

  it "persists todo list content with checked state for task items" do
    owner = User.create!(email: "blocks-todo-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Todo blocks", slug: "todo-blocks")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Todos")
    block = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "paragraph")
    sign_in owner

    patch page_block_path(workspace_slug: workspace.slug, page_id: page.id, id: block.id),
          params: {
            block: {
              block_type: "todo_list",
              content_json: {
                type: "doc",
                content: [
                  {
                    type: "taskList",
                    content: [
                      {
                        type: "taskItem",
                        attrs: { checked: false },
                        content: [
                          { type: "paragraph", content: [ { type: "text", text: "Unchecked item" } ] }
                        ]
                      },
                      {
                        type: "taskItem",
                        attrs: { checked: true },
                        content: [
                          { type: "paragraph", content: [ { type: "text", text: "Checked item" } ] }
                        ]
                      }
                    ]
                  }
                ]
              }
            }
          },
          as: :json

    expect(response).to have_http_status(:ok)
    expect(block.reload.block_type).to eq("todo_list")
    task_items = block.content_json.dig("content", 0, "content")
    expect(task_items.length).to eq(2)
    expect(task_items.first.dig("attrs", "checked")).to eq(false)
    expect(task_items.last.dig("attrs", "checked")).to eq(true)
  end

  it "creates sibling child blocks with unique positions via add-block flow" do
    owner = User.create!(email: "blocks-child-create-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Child create", slug: "child-create")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Child create page")
    parent = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "paragraph")
    sign_in owner

    2.times do
      post page_blocks_path(workspace_slug: workspace.slug, page_id: page.id),
           params: { block: { parent_block_id: parent.id, block_type: "paragraph" } }
      expect(response).to redirect_to(page_path(workspace_slug: workspace.slug, id: page.id))
    end

    sibling_positions = page.blocks.active.where(parent_block_id: parent.id).order(:position).pluck(:position)

    expect(sibling_positions.length).to eq(2)
    expect(sibling_positions.uniq.length).to eq(2)
    expect(sibling_positions.last).to be > sibling_positions.first
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

  it "renders drag-and-drop action bindings for block items" do
    owner = User.create!(email: "blocks-reorder-binding-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Reorder bindings", slug: "reorder-bindings")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Reorder binding page")
    Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "paragraph")
    sign_in owner

    get page_path(workspace_slug: workspace.slug, id: page.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("dragstart->block-list#handleDragStart")
    expect(response.body).to include("dragenter->block-list#handleDragEnter")
    expect(response.body).to include("dragleave->block-list#handleDragLeave")
    expect(response.body).to include("dragover->block-list#handleDragOver")
    expect(response.body).to include("drop->block-list#handleDrop")
    expect(response.body).to include("dragend->block-list#handleDragEnd")
    expect(response.body).to include("class=\"notae-doc-handle\"")
    expect(response.body).to include("title=\"Drag block\"")
    expect(response.body).to include("draggable=\"true\"")
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

  it "returns rendered media html after image upload so the nota can update in place" do
    owner = User.create!(email: "blocks-image-upload-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Image blocks", slug: "image-blocks")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Images")
    block = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "image")
    sign_in owner

    Tempfile.create([ "block-upload", ".png" ]) do |file|
      file.write("fake-png-data")
      file.rewind
      uploaded_file = Rack::Test::UploadedFile.new(file.path, "image/png")

      patch attach_page_block_path(workspace_slug: workspace.slug, page_id: page.id, id: block.id),
            params: { block: { file: uploaded_file } },
            headers: { "ACCEPT" => "application/json" }
    end

    expect(response).to have_http_status(:ok)
    payload = JSON.parse(response.body)
    expect(payload["html"]).to include("notae-doc-image")
    expect(payload["html"]).to include('loading="lazy"')
    expect(payload["html"]).to include('decoding="async"')
    expect(payload["html"]).not_to include("notae-doc-dropzone")
    expect(payload["html"]).to include('target="_blank"')
    expect(payload["html"]).to include('rel="noopener noreferrer"')
    expect(payload["page_updated_at"]).to be_present
    expect(block.reload.asset).to be_attached
  end

  it "renders valid upload controller bindings for unattached media blocks" do
    owner = User.create!(email: "blocks-upload-bindings-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Upload bindings", slug: "upload-bindings")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Upload bindings page")
    block = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "image")
    sign_in owner

    get page_path(workspace_slug: workspace.slug, id: page.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-controller="block-upload"')
    expect(response.body).to include(%(data-block-upload-url-value="/w/#{workspace.slug}/pages/#{page.id}/blocks/#{block.id}/attach"))
    expect(response.body).not_to include("&quot;block-upload&quot;")
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

  it "renders a single media insertion action and previews uploaded media blocks" do
    owner = User.create!(email: "blocks-media-menu-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Media menu", slug: "media-menu")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Media menu page")
    Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "paragraph")
    video_block = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "video")
    audio_block = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "file")
    Tempfile.create([ "block-video-preview", ".mp4" ]) do |file|
      file.write("fake video payload")
      file.rewind
      video_block.asset.attach(io: file, filename: "clip.mp4", content_type: "video/mp4")
    end
    Tempfile.create([ "block-audio-preview", ".mp3" ]) do |file|
      file.write("fake audio payload")
      file.rewind
      audio_block.asset.attach(io: file, filename: "clip.mp3", content_type: "audio/mpeg")
    end
    sign_in owner

    get page_path(workspace_slug: workspace.slug, id: page.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Add media")
    expect(response.body).not_to include("Embed image")
    expect(response.body).not_to include("Embed video")
    expect(response.body).to include("notae-doc-video")
    expect(response.body).to include("notae-doc-audio")
    expect(response.body).not_to include("Drag and drop media")
    expect(response.body).not_to include("accept=\"image/*,video/*,audio/*\"")
  end

  it "creates a media block from the block menu without overwriting the current text block" do
    owner = User.create!(email: "blocks-media-insert-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Media insert", slug: "media-insert")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Media insert page")
    first = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "paragraph")
    second = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "heading_1")
    sign_in owner

    post command_page_block_path(workspace_slug: workspace.slug, page_id: page.id, id: first.id),
         params: { block_command: { command: "insert_media", target: "media" } }

    media_block = page.blocks.active.find_by(block_type: "file")
    expect(response).to redirect_to(page_path(workspace_slug: workspace.slug, id: page.id, anchor: "block_#{media_block.id}"))

    ordered_blocks = page.blocks.active.roots.ordered.to_a
    expect(ordered_blocks.map(&:id)).to eq([ first.id, media_block.id, second.id ])
    expect(first.reload.block_type).to eq("paragraph")
    expect(second.reload.block_type).to eq("heading_1")

    get page_path(workspace_slug: workspace.slug, id: page.id)

    expect(response.body).to include("Drag and drop media")
    expect(response.body).to include("accept=\"image/*,video/*,audio/*\"")
  end

  it "supports all turn-into menu command targets including page creation and synced blocks" do
    owner = User.create!(email: "blocks-turn-into-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Turn into", slug: "turn-into")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Turn Into Page")
    block = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "paragraph")
    sign_in owner

    targets = {
      "text" => "paragraph",
      "heading_1" => "heading_1",
      "heading_2" => "heading_2",
      "heading_3" => "heading_3",
      "bulleted_list" => "bullet_list",
      "numbered_list" => "ordered_list",
      "todo_list" => "todo_list",
      "toggle_list" => "toggle_list",
      "code" => "code_block",
      "quote" => "blockquote",
      "callout" => "callout",
      "block_equation" => "equation",
      "toggle_heading_1" => "toggle_heading_1",
      "toggle_heading_2" => "toggle_heading_2",
      "toggle_heading_3" => "toggle_heading_3",
      "columns_2" => "columns_2",
      "columns_3" => "columns_3",
      "columns_4" => "columns_4",
      "columns_5" => "columns_5"
    }

    targets.each do |target, expected_type|
      post command_page_block_path(workspace_slug: workspace.slug, page_id: page.id, id: block.id),
           params: { block_command: { command: "turn_into", target: target } }

      expect(response).to have_http_status(:redirect)
      expect(block.reload.block_type).to eq(expected_type)
    end

    expect do
      post command_page_block_path(workspace_slug: workspace.slug, page_id: page.id, id: block.id),
           params: { block_command: { command: "turn_into", target: "page" } }
    end.to change(Page, :count).by(1)

    child_page = nil
    expect do
      post command_page_block_path(workspace_slug: workspace.slug, page_id: page.id, id: block.id),
           params: { block_command: { command: "turn_into", target: "page_in" } }
      child_page = Page.order(:created_at).last
    end.to change(Page, :count).by(1)
    expect(child_page.parent_page_id).to eq(page.id)

    expect do
      post command_page_block_path(workspace_slug: workspace.slug, page_id: page.id, id: block.id),
           params: { block_command: { command: "turn_into", target: "synced_block" } }
    end.to change(Block, :count).by(1)
    synced_copy = Block.order(:created_at).last
    expect(synced_copy.content_json["notae_synced_source_id"]).to eq(block.id.to_s)
  end

  it "toggles applied turn-into styles off when selected again" do
    owner = User.create!(email: "blocks-turn-toggle-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Turn toggle", slug: "turn-toggle")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Turn toggle page")
    block = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "paragraph")
    sign_in owner

    post command_page_block_path(workspace_slug: workspace.slug, page_id: page.id, id: block.id),
         params: { block_command: { command: "turn_into", target: "heading_1" } }
    expect(block.reload.block_type).to eq("heading_1")

    post command_page_block_path(workspace_slug: workspace.slug, page_id: page.id, id: block.id),
         params: { block_command: { command: "turn_into", target: "heading_1" } }
    expect(block.reload.block_type).to eq("paragraph")

    post command_page_block_path(workspace_slug: workspace.slug, page_id: page.id, id: block.id),
         params: { block_command: { command: "turn_into", target: "bulleted_list" } }
    expect(block.reload.block_type).to eq("bullet_list")

    post command_page_block_path(workspace_slug: workspace.slug, page_id: page.id, id: block.id),
         params: { block_command: { command: "turn_into", target: "bulleted_list" } }
    expect(block.reload.block_type).to eq("paragraph")
  end

  it "preserves media blocks when applying a column layout turn-into option" do
    owner = User.create!(email: "blocks-media-columns-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Media columns", slug: "media-columns")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Media columns page")
    block = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "image")
    sign_in owner

    Tempfile.create([ "block-image-columns", ".png" ]) do |file|
      file.write("fake image payload")
      file.rewind
      block.asset.attach(io: file, filename: "layout.png", content_type: "image/png")
    end

    post command_page_block_path(workspace_slug: workspace.slug, page_id: page.id, id: block.id),
         params: { block_command: { command: "turn_into", target: "columns_3" } }

    expect(response).to have_http_status(:redirect)
    expect(block.reload.block_type).to eq("image")
    expect(block.layout_columns_count).to eq(3)
    expect(block.asset).to be_attached

    get page_path(workspace_slug: workspace.slug, id: page.id)

    expect(response.body).to include("notae-doc-image")
    expect(response.body).to include("is-layout-columns-3")

    post command_page_block_path(workspace_slug: workspace.slug, page_id: page.id, id: block.id),
         params: { block_command: { command: "turn_into", target: "columns_3" } }

    expect(block.reload.layout_columns_count).to be_nil
    expect(block.asset).to be_attached
  end

  it "supports color, duplicate, move, delete, and suggest edits commands" do
    owner = User.create!(email: "blocks-command-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Command blocks", slug: "command-blocks")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Command page")
    destination_page = Page.create!(workspace: workspace, created_by: owner, title: "Destination page")
    block = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "paragraph")
    sign_in owner

    %w[default gray brown orange yellow green blue purple pink red].each do |color|
      post command_page_block_path(workspace_slug: workspace.slug, page_id: page.id, id: block.id),
           params: { block_command: { command: "color", color: color } }
      expect(response).to have_http_status(:redirect)
      expect(block.reload.content_json["notae_color"]).to eq(color)
    end

    post command_page_block_path(workspace_slug: workspace.slug, page_id: page.id, id: block.id),
         params: { block_command: { command: "color", color: "red" } }
    expect(response).to have_http_status(:redirect)
    expect(block.reload.content_json["notae_color"]).to eq("default")

    %w[default peach lemon mint sky lavender rose].each do |highlight|
      post command_page_block_path(workspace_slug: workspace.slug, page_id: page.id, id: block.id),
           params: { block_command: { command: "highlight", highlight: highlight } }
      expect(response).to have_http_status(:redirect)
      expect(block.reload.content_json["notae_highlight"]).to eq(highlight)
    end

    post command_page_block_path(workspace_slug: workspace.slug, page_id: page.id, id: block.id),
         params: { block_command: { command: "highlight", highlight: "rose" } }
    expect(response).to have_http_status(:redirect)
    expect(block.reload.content_json["notae_highlight"]).to eq("default")

    expect do
      post command_page_block_path(workspace_slug: workspace.slug, page_id: page.id, id: block.id),
           params: { block_command: { command: "duplicate" } }
    end.to change(Block, :count).by(1)

    post command_page_block_path(workspace_slug: workspace.slug, page_id: page.id, id: block.id),
         params: { block_command: { command: "move_to", target_page_id: destination_page.id } }
    expect(response).to have_http_status(:redirect)
    expect(block.reload.page_id).to eq(destination_page.id)

    expect do
      post command_page_block_path(workspace_slug: workspace.slug, page_id: destination_page.id, id: block.id),
           params: { block_command: { command: "suggest_edits", note: "Please tighten this copy." } }
    end.to change(Comment, :count).by(1)
    expect(Comment.order(:created_at).last.body).to include("tighten this copy")

    post command_page_block_path(workspace_slug: workspace.slug, page_id: destination_page.id, id: block.id),
         params: { block_command: { command: "delete" } }
    expect(response).to have_http_status(:redirect)
    expect(block.reload.archived_at).to be_present
  end
end
