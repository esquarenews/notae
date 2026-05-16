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

  it "serves block editor content separately for lazy editor hydration" do
    owner = User.create!(email: "blocks-content-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Block content", slug: "block-content")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Lazy editor")
    block = Block.create!(
      workspace: workspace,
      page: page,
      created_by: owner,
      block_type: "paragraph",
      content_json: {
        "type" => "doc",
        "content" => [
          {
            "type" => "paragraph",
            "content" => [ { "type" => "text", "text" => "Loaded after focus" } ]
          }
        ]
      }
    )
    sign_in owner

    get content_page_block_path(workspace_slug: workspace.slug, page_id: page.id, id: block.id),
        headers: { "Accept" => "application/json" }

    expect(response).to have_http_status(:ok)
    payload = JSON.parse(response.body)
    expect(payload["id"]).to eq(block.id)
    expect(payload["block_type"]).to eq("paragraph")
    expect(payload.dig("content_json", "content", 0, "content", 0, "text")).to eq("Loaded after focus")
  end

  it "broadcasts synced block updates to every touched page while skipping only the edited block for the same tab" do
    owner = User.create!(email: "blocks-synced-broadcast-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Synced broadcasts", slug: "synced-broadcasts")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    source_page = Page.create!(workspace: workspace, created_by: owner, title: "Source page")
    copy_page = Page.create!(workspace: workspace, created_by: owner, title: "Copy page")
    source_block = Block.create!(workspace: workspace, page: source_page, created_by: owner, block_type: "paragraph")
    source_block.update!(
      block_type: "synced_block",
      content_json: {
        "type" => "doc",
        "content" => [
          {
            "type" => "paragraph",
            "content" => [ { "type" => "text", "text" => "Source content" } ]
          }
        ],
        "notae_synced_source_id" => source_block.id.to_s
      }
    )
    synced_copy = Block.create!(
      workspace: workspace,
      page: copy_page,
      created_by: owner,
      block_type: "synced_block",
      content_json: {
        "type" => "doc",
        "content" => [
          {
            "type" => "paragraph",
            "content" => [ { "type" => "text", "text" => "Source content" } ]
          }
        ],
        "notae_synced_source_id" => source_block.id.to_s
      }
    )
    sign_in owner
    allow(ActionCable.server).to receive(:broadcast)

    patch page_block_path(workspace_slug: workspace.slug, page_id: source_page.id, id: source_block.id),
          params: {
            block: {
              block_type: "synced_block",
              content_json: {
                type: "doc",
                content: [
                  {
                    type: "paragraph",
                    content: [ { type: "text", text: "Updated everywhere" } ]
                  }
                ]
              }
            }
          },
          headers: { "X-Notae-Client-Session" => "tab-123" },
          as: :json

    expect(response).to have_http_status(:ok)
    expect(synced_copy.reload.content_json.dig("content", 0, "content", 0, "text")).to eq("Updated everywhere")
    expect(ActionCable.server).to have_received(:broadcast).with(
      "page:#{source_page.id}:collaboration",
      hash_including(
        type: "block_updated",
        client_session_id: "tab-123",
        origin_block_id: source_block.id,
        block: hash_including(id: source_block.id)
      )
    )
    expect(ActionCable.server).to have_received(:broadcast).with(
      "page:#{copy_page.id}:collaboration",
      hash_including(
        type: "block_updated",
        client_session_id: "tab-123",
        origin_block_id: source_block.id,
        block: hash_including(id: synced_copy.id)
      )
    )
  end

  it "does not resolve synced block roots from another workspace when applying commands" do
    owner = User.create!(email: "blocks-synced-cross-workspace-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Synced local workspace", slug: "synced-local-workspace")
    other_workspace = Workspace.create!(name: "Synced other workspace", slug: "synced-other-workspace")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: other_workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Local page")
    other_page = Page.create!(workspace: other_workspace, created_by: owner, title: "Other page")
    other_source = Block.create!(
      workspace: other_workspace,
      page: other_page,
      created_by: owner,
      block_type: "paragraph",
      content_json: {
        "type" => "doc",
        "content" => [
          {
            "type" => "paragraph",
            "content" => [ { "type" => "text", "text" => "Other workspace secret" } ]
          }
        ]
      }
    )
    local_copy = Block.create!(
      workspace: workspace,
      page: page,
      created_by: owner,
      block_type: "synced_block",
      content_json: {
        "type" => "doc",
        "content" => [
          {
            "type" => "paragraph",
            "content" => [ { "type" => "text", "text" => "Local content" } ]
          }
        ],
        "notae_synced_source_id" => other_source.id.to_s
      }
    )
    sign_in owner

    post command_page_block_path(workspace_slug: workspace.slug, page_id: page.id, id: local_copy.id),
         params: { block_command: { command: "color", color: "red" } }

    expect(response).to have_http_status(:redirect)
    expect(local_copy.reload.content_json.dig("content", 0, "content", 0, "text")).to eq("Local content")
    expect(local_copy.content_json["notae_synced_source_id"]).to eq(other_source.id.to_s)
    expect(local_copy.content_json["notae_color"]).to eq("red")
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

  it "creates a new top-level block inline over turbo stream without jumping to the page shell" do
    owner = User.create!(email: "blocks-inline-create-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Inline create", slug: "inline-create")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Inline create page")
    sign_in owner

    expect do
      post page_blocks_path(workspace_slug: workspace.slug, page_id: page.id),
           params: { block: { block_type: "paragraph" } },
           as: :turbo_stream
    end.to change { page.blocks.count }.by(1)

    created_block = page.blocks.order(:created_at).last

    expect(response).to have_http_status(:ok)
    expect(response).not_to be_redirect
    expect(response.media_type).to eq(Mime[:turbo_stream].to_s)
    expect(response.body).to include('turbo-stream action="replace" target="page_flash_messages"')
    expect(response.body).to include("Block created.")
    expect(response.body).to include('turbo-stream action="append" target="notae_doc_tree_root"')
    expect(response.body).to include(%(id="block_#{created_block.id}"))
  end

  it "creates a gantt embed block after the reference block for paste-driven embeds" do
    owner = User.create!(email: "blocks-gantt-embed-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Gantt embed blocks", slug: "gantt-embed-blocks")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Embed page")
    database = Database.create!(workspace: workspace, name: "Roadmap")
    first = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "paragraph")
    second = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "paragraph")
    sign_in owner

    post page_blocks_path(workspace_slug: workspace.slug, page_id: page.id),
         params: {
           insert_after_id: first.id,
           block: {
             block_type: "gantt_embed",
             content_json: {
               notae_gantt_workspace_slug: workspace.slug,
               notae_gantt_database_id: database.id
             }
           }
         },
         as: :turbo_stream

    expect(response).to have_http_status(:ok)
    inserted = page.blocks.active.where(block_type: "gantt_embed").sole
    expect(page.blocks.active.roots.ordered.pluck(:id)).to eq([ first.id, inserted.id, second.id ])
    expect(inserted.gantt_workspace_slug).to eq(workspace.slug)
    expect(inserted.gantt_database_id).to eq(database.id.to_s)
    expect(response.body).to include(%(id="block_#{inserted.id}"))
  end

  it "renders gantt embed blocks as live chart iframes inside the Nota" do
    owner = User.create!(email: "blocks-gantt-render-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Gantt render blocks", slug: "gantt-render-blocks")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Embed page")
    database = Database.create!(workspace: workspace, name: "Roadmap")
    Block.create!(
      workspace: workspace,
      page: page,
      created_by: owner,
      block_type: "gantt_embed",
      content_json: {
        "notae_gantt_workspace_slug" => workspace.slug,
        "notae_gantt_database_id" => database.id.to_s
      }
    )
    sign_in owner

    get page_path(workspace_slug: workspace.slug, id: page.id)

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    iframe = html.at_css(".notae-doc-gantt-embed-frame")
    expect(iframe).to be_present
    expect(iframe["src"]).to include("/w/#{workspace.slug}/databases/#{database.id}/gantt_embed")
  end

  it "creates a graph embed block after the reference block for paste-driven embeds" do
    owner = User.create!(email: "blocks-graph-embed-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Graph embed blocks", slug: "graph-embed-blocks")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Embed page")
    database = Database.create!(workspace: workspace, name: "Metrics")
    first = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "paragraph")
    second = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "paragraph")
    sign_in owner

    post page_blocks_path(workspace_slug: workspace.slug, page_id: page.id),
         params: {
           insert_after_id: first.id,
           block: {
             block_type: "graph_embed",
             content_json: {
               notae_graph_workspace_slug: workspace.slug,
               notae_graph_database_id: database.id
             }
           }
         },
         as: :turbo_stream

    expect(response).to have_http_status(:ok)
    inserted = page.blocks.active.where(block_type: "graph_embed").sole
    expect(page.blocks.active.roots.ordered.pluck(:id)).to eq([ first.id, inserted.id, second.id ])
    expect(inserted.graph_workspace_slug).to eq(workspace.slug)
    expect(inserted.graph_database_id).to eq(database.id.to_s)
    expect(response.body).to include(%(id="block_#{inserted.id}"))
  end

  it "renders graph embed blocks as live chart iframes inside the Nota" do
    owner = User.create!(email: "blocks-graph-render-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Graph render blocks", slug: "graph-render-blocks")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Embed page")
    database = Database.create!(workspace: workspace, name: "Metrics")
    Block.create!(
      workspace: workspace,
      page: page,
      created_by: owner,
      block_type: "graph_embed",
      content_json: {
        "notae_graph_workspace_slug" => workspace.slug,
        "notae_graph_database_id" => database.id.to_s
      }
    )
    sign_in owner

    get page_path(workspace_slug: workspace.slug, id: page.id)

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    iframe = html.at_css(".notae-doc-graph-embed-frame")
    expect(iframe).to be_present
    expect(iframe["src"]).to include("/w/#{workspace.slug}/databases/#{database.id}/graph_embed")
  end

  it "adds a blank block above the current block from the block menu command" do
    owner = User.create!(email: "blocks-add-above-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Add above", slug: "add-above")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Add above page")
    first = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "paragraph")
    second = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "paragraph")
    sign_in owner

    post command_page_block_path(workspace_slug: workspace.slug, page_id: page.id, id: second.id),
         params: { block_command: { command: "add_block_above" } }

    inserted = page.blocks.active.where.not(id: [ first.id, second.id ]).sole
    ordered_ids = page.blocks.active.roots.ordered.pluck(:id)

    expect(response).to redirect_to(page_path(workspace_slug: workspace.slug, id: page.id, anchor: "block_#{inserted.id}"))
    expect(ordered_ids).to eq([ first.id, inserted.id, second.id ])
    expect(inserted.block_type).to eq("paragraph")
    expect(inserted.content_json).to eq(Block::DEFAULT_CONTENT)
  end

  it "adds a blank block below the current block from the block menu command" do
    owner = User.create!(email: "blocks-add-below-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Add below", slug: "add-below")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Add below page")
    first = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "paragraph")
    second = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "paragraph")
    sign_in owner

    post command_page_block_path(workspace_slug: workspace.slug, page_id: page.id, id: first.id),
         params: { block_command: { command: "add_block_below" } }

    inserted = page.blocks.active.where.not(id: [ first.id, second.id ]).sole
    ordered_ids = page.blocks.active.roots.ordered.pluck(:id)

    expect(response).to redirect_to(page_path(workspace_slug: workspace.slug, id: page.id, anchor: "block_#{inserted.id}"))
    expect(ordered_ids).to eq([ first.id, inserted.id, second.id ])
    expect(inserted.block_type).to eq("paragraph")
    expect(inserted.content_json).to eq(Block::DEFAULT_CONTENT)
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

  it "reorders blocks into and out of nested indentation levels" do
    owner = User.create!(email: "blocks-indent-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Indent blocks", slug: "indent-blocks")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Indent page")
    parent = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "paragraph")
    child_candidate = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "paragraph")
    sign_in owner

    patch reorder_page_block_path(workspace_slug: workspace.slug, page_id: page.id, id: child_candidate.id),
          params: { target_parent_id: parent.id, target_index: 0 },
          as: :json

    expect(response).to have_http_status(:ok)
    expect(child_candidate.reload.parent_block_id).to eq(parent.id)
    expect(page.blocks.active.where(parent_block_id: parent.id).ordered.pluck(:id)).to eq([ child_candidate.id ])

    patch reorder_page_block_path(workspace_slug: workspace.slug, page_id: page.id, id: child_candidate.id),
          params: { target_parent_id: nil, target_index: 1 },
          as: :json

    expect(response).to have_http_status(:ok)
    expect(child_candidate.reload.parent_block_id).to be_nil
    expect(page.blocks.active.roots.ordered.pluck(:id)).to eq([ parent.id, child_candidate.id ])
  end

  it "rerenders the document canvas over turbo stream when indenting a block" do
    owner = User.create!(email: "blocks-indent-stream-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Indent stream blocks", slug: "indent-stream-blocks")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Indent stream page")
    parent = Block.create!(
      workspace: workspace,
      page: page,
      created_by: owner,
      block_type: "paragraph",
      content_json: {
        "type" => "doc",
        "content" => [
          { "type" => "paragraph", "content" => [ { "type" => "text", "text" => "Parent block" } ] }
        ]
      }
    )
    child_candidate = Block.create!(
      workspace: workspace,
      page: page,
      created_by: owner,
      block_type: "paragraph",
      content_json: {
        "type" => "doc",
        "content" => [
          { "type" => "paragraph", "content" => [ { "type" => "text", "text" => "Indented block text" } ] }
        ]
      }
    )
    sign_in owner

    patch reorder_page_block_path(workspace_slug: workspace.slug, page_id: page.id, id: child_candidate.id),
          params: { target_parent_id: parent.id, target_index: 0 },
          as: :turbo_stream

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq(Mime[:turbo_stream].to_s)
    expect(response.body).to include('turbo-stream action="replace" target="notae_doc_canvas"')
    expect(response.body).to include("Indented block text")
    expect(response.body).to include(%(id="block_#{child_candidate.id}"))
    expect(child_candidate.reload.parent_block_id).to eq(parent.id)
  end

  it "renders drag-and-drop action bindings for block items" do
    owner = User.create!(email: "blocks-reorder-binding-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Reorder bindings", slug: "reorder-bindings")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Reorder binding page")
    block = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "paragraph")
    sign_in owner

    get page_path(workspace_slug: workspace.slug, id: page.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("dragstart->block-list#handleDragStart")
    expect(response.body).to include("dragenter->block-list#handleDragEnter")
    expect(response.body).to include("dragleave->block-list#handleDragLeave")
    expect(response.body).to include("dragover->block-list#handleDragOver")
    expect(response.body).to include("drop->block-list#handleDrop")
    expect(response.body).to include("dragend->block-list#handleDragEnd")
    expect(response.body).to include("pointerdown->block-list#prepareDragStart")
    expect(response.body).to include("class=\"notae-doc-handle\"")
    expect(response.body).to include("title=\"Drag block\"")
    expect(response.body).to include("draggable=\"true\"")
    expect(response.body).to include(panel_page_block_path(workspace_slug: workspace.slug, page_id: page.id, id: block.id))

    get panel_page_block_path(workspace_slug: workspace.slug, page_id: page.id, id: block.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Indent")
    expect(response.body).to include("Outdent")
    expect(response.body).to include("data-turbo-stream=\"true\"")
  end

  it "renders the updated block menu actions without legacy page conversion targets" do
    owner = User.create!(email: "blocks-menu-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Menu blocks", slug: "menu-blocks")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Menu page")
    block = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "paragraph")
    sign_in owner

    get panel_page_block_path(workspace_slug: workspace.slug, page_id: page.id, id: block.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('class="notae-menu-item-label">Page</span>')
    expect(response.body).not_to include('class="notae-menu-item-label">Page in</span>')
    expect(response.body).to include("Add block above")
    expect(response.body).to include("Add block below")
    expect(response.body).to include("Turn this block into whiteboard")
    expect(response.body).to include("Delete block")

    document = Nokogiri::HTML(response.body)
    delete_form = document.at_css("form[data-turbo-confirm='Delete this block? This cannot be undone.']")
    expect(delete_form).to be_present
    expect(delete_form.at_css(".notae-block-menu-item.is-danger").text.squish).to include("Delete block")

    actions_section = response.body.match(/<section class="notae-block-menu-section">\s*<h4>Actions<\/h4>(.*?)<\/section>/m)
    expect(actions_section).to be_present

    action_markup = actions_section[1]
    expect(action_markup.index("Add block above")).to be < action_markup.index("Add block below")
    expect(action_markup.index("Add block below")).to be < action_markup.index("Indent")
    expect(action_markup.index("Indent")).to be < action_markup.index("Outdent")
    expect(action_markup.index("Duplicate")).to be < action_markup.index("Turn this block into whiteboard")
    expect(action_markup.index("Turn this block into whiteboard")).to be < action_markup.index("Delete block")
  end

  it "keeps page flash notices fixed to the visible viewport" do
    stylesheet = Rails.root.join("app/assets/stylesheets/application.css").read

    expect(stylesheet).to include(".notae-content > #notae_flash_messages {\n  position: fixed;\n  top: var(--notae-topbar-content-clearance);\n  left: 0;\n  right: 0;")
    expect(stylesheet).to include("  height: 0;\n  margin: 0;\n  overflow: visible;")
    expect(stylesheet).to include(".notae-content > #notae_flash_messages .notae-flash-stack {\n  width: min(50%, 760px);")
    expect(stylesheet).to include(".notae-page-inline-flash-host,\n.notae-db-inline-flash-host,")
    expect(stylesheet).to include(".notae-settings-inline-flash-host,\n.notae-auth-flash-host {\n  position: fixed;\n  top: var(--notae-topbar-content-clearance);\n  left: 0;\n  right: 0;")
    expect(stylesheet).to include(".notae-page-inline-flash-host .notae-flash-stack,\n.notae-db-inline-flash-host .notae-flash-stack,")
    expect(stylesheet).to include(".notae-settings-inline-flash-host .notae-flash-stack,\n.notae-auth-flash-host .notae-flash-stack {\n  width: min(44rem, calc(100% - 1.2rem));")
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

  it "exports the current block as markdown without including the rest of the page" do
    owner = User.create!(email: "blocks-markdown-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Block markdown", slug: "block-markdown")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Export page")
    target_block = Block.create!(
      workspace: workspace,
      page: page,
      created_by: owner,
      block_type: "paragraph",
      content_json: {
        "type" => "doc",
        "content" => [
          { "type" => "heading", "attrs" => { "level" => 3 }, "content" => [ { "type" => "text", "text" => "Current block" } ] },
          { "type" => "paragraph", "content" => [ { "type" => "text", "text" => "Only this block" } ] }
        ]
      }
    )
    Block.create!(
      workspace: workspace,
      page: page,
      created_by: owner,
      block_type: "paragraph",
      content_json: {
        "type" => "doc",
        "content" => [ { "type" => "paragraph", "content" => [ { "type" => "text", "text" => "Other block" } ] } ]
      }
    )
    sign_in owner

    get export_markdown_page_block_path(workspace_slug: workspace.slug, page_id: page.id, id: target_block.id)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/markdown")
    expect(response.body).to include("### Current block")
    expect(response.body).to include("Only this block")
    expect(response.body).not_to include("Other block")
    expect(response.body).not_to include("# Export page")
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

    get export_markdown_page_block_path(workspace_slug: workspace.slug, page_id: page.id, id: block.id)

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
    block = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "paragraph")
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
    expect(response.body).to include("notae-doc-video")
    expect(response.body).to include("notae-doc-audio")
    expect(response.body).not_to include("Drag and drop media")
    expect(response.body).not_to include("accept=\"image/*,video/*,audio/*\"")

    get panel_page_block_path(workspace_slug: workspace.slug, page_id: page.id, id: block.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Add media")
    expect(response.body).not_to include("Embed image")
    expect(response.body).not_to include("Embed video")
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
      "heading_4" => "heading_4",
      "bulleted_list" => "bullet_list",
      "numbered_list" => "ordered_list",
      "todo_list" => "todo_list",
      "toggle_list" => "toggle_list",
      "code" => "code_block",
      "quote" => "blockquote",
      "callout" => "callout",
      "block_equation" => "equation",
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

  it "turns hard-return lines into separate bullet items and restores them as hard breaks when toggled off" do
    owner = User.create!(email: "blocks-hard-break-list-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Hard break lists", slug: "hard-break-lists")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Hard break list page")
    block = Block.create!(
      workspace: workspace,
      page: page,
      created_by: owner,
      block_type: "paragraph",
      content_json: {
        "type" => "doc",
        "content" => [
          {
            "type" => "paragraph",
            "content" => [
              { "type" => "text", "text" => "First line" },
              { "type" => "hardBreak" },
              { "type" => "text", "text" => "Second line" },
              { "type" => "hardBreak" },
              { "type" => "text", "text" => "Third line" }
            ]
          }
        ]
      }
    )
    sign_in owner

    post command_page_block_path(workspace_slug: workspace.slug, page_id: page.id, id: block.id),
         params: { block_command: { command: "turn_into", target: "bulleted_list" } }

    expect(response).to have_http_status(:redirect)
    expect(block.reload.block_type).to eq("bullet_list")
    list_items = block.content_json.dig("content", 0, "content")
    expect(list_items.size).to eq(3)
    expect(list_items.map { |item| item.dig("content", 0, "content", 0, "text") }).to eq([ "First line", "Second line", "Third line" ])

    post command_page_block_path(workspace_slug: workspace.slug, page_id: page.id, id: block.id),
         params: { block_command: { command: "turn_into", target: "bulleted_list" } }

    expect(block.reload.block_type).to eq("paragraph")
    paragraph_content = block.content_json.dig("content", 0, "content")
    expect(paragraph_content.map { |node| node["type"] }).to eq([ "text", "hardBreak", "text", "hardBreak", "text" ])
    expect(paragraph_content.filter_map { |node| node["text"] }).to eq([ "First line", "Second line", "Third line" ])
  end

  it "updates style commands inline over turbo stream instead of redirecting the full page" do
    owner = User.create!(email: "blocks-inline-style-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Inline style blocks", slug: "inline-style-blocks")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Inline style page")
    block = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "paragraph")
    sign_in owner

    post command_page_block_path(workspace_slug: workspace.slug, page_id: page.id, id: block.id),
         params: { block_command: { command: "color", color: "blue" } },
         as: :turbo_stream

    expect(response).to have_http_status(:ok)
    expect(response).not_to be_redirect
    expect(response.media_type).to eq(Mime[:turbo_stream].to_s)
    expect(response.body).to include('turbo-stream action="replace" target="page_flash_messages"')
    expect(response.body).to include("Color updated.")
    expect(response.body).to include(%(turbo-stream action="replace" target="block_#{block.id}"))
    expect(block.reload.content_json["notae_color"]).to eq("blue")
  end

  it "updates basic turn-into commands inline over turbo stream" do
    owner = User.create!(email: "blocks-inline-turn-into-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Inline turn into blocks", slug: "inline-turn-into-blocks")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Inline turn into page")
    block = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "paragraph")
    sign_in owner

    post command_page_block_path(workspace_slug: workspace.slug, page_id: page.id, id: block.id),
         params: { block_command: { command: "turn_into", target: "todo_list" } },
         as: :turbo_stream

    expect(response).to have_http_status(:ok)
    expect(response).not_to be_redirect
    expect(response.media_type).to eq(Mime[:turbo_stream].to_s)
    expect(response.body).to include('turbo-stream action="replace" target="page_flash_messages"')
    expect(response.body).to include("Block updated.")
    expect(response.body).to include(%(turbo-stream action="replace" target="block_#{block.id}"))
    expect(block.reload.block_type).to eq("todo_list")
  end

  it "turns a block into a whiteboard from the block menu and renders the whiteboard editor" do
    owner = User.create!(email: "blocks-whiteboard-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Whiteboard blocks", slug: "whiteboard-blocks")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Whiteboard page")
    block = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "paragraph")
    sign_in owner

    post command_page_block_path(workspace_slug: workspace.slug, page_id: page.id, id: block.id),
         params: { block_command: { command: "turn_into", target: "whiteboard" } },
         as: :turbo_stream

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(%(turbo-stream action="replace" target="block_#{block.id}"))
    expect(response.body).to include("data-controller=\"whiteboard\"")
    expect(response.body).to include("Open whiteboard")
    expect(response.body).to include("Back to nota")
    document = Nokogiri::HTML(response.body)
    expect(document.at_css(".notae-whiteboard-tool[aria-label='Pencil'] svg.notae-whiteboard-tool-icon")).to be_present
    expect(document.at_css(".notae-whiteboard-tool[aria-label='Marker'] svg.notae-whiteboard-tool-icon")).to be_present
    expect(document.at_css(".notae-whiteboard-tool[aria-label='Block eraser'] svg.notae-whiteboard-tool-icon")).to be_present
    expect(document.at_css(".notae-whiteboard-tool[aria-label='Clear all'] svg.notae-whiteboard-tool-icon")).to be_present
    expect(document.at_css(".notae-whiteboard-color-picker input[type='color'][data-whiteboard-target='colorInput']")).to be_present
    expect(document.at_css(".notae-whiteboard-color-grid")).to be_blank
    expect(document.css(".notae-whiteboard-color")).to be_blank
    expect(document.at_css(".notae-whiteboard-canvas[tabindex='0']")).to be_present
    diameter_slider = document.at_css(".notae-whiteboard-diameter input[type='range'][data-whiteboard-target='diameterInput']")
    expect(diameter_slider).to be_present
    expect(diameter_slider["min"]).to eq("1")
    expect(diameter_slider["max"]).to eq("10")
    expect(diameter_slider["orient"]).to eq("vertical")

    block.reload
    expect(block.block_type).to eq("whiteboard")
    expect(block.content_json).to include(
      "type" => "whiteboard",
      "version" => 1,
      "strokes" => [],
      "whiteboard_autofocus" => true
    )
    expect(block.content_json.dig("board", "width")).to eq(1600)
    expect(block.content_json.dig("board", "height")).to eq(1000)
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

  it "creates linked notas and grids from block actions and opens them in split panes" do
    owner = User.create!(email: "blocks-linked-create-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Linked create blocks", slug: "linked-create-blocks")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    source_page = Page.create!(workspace: workspace, created_by: owner, title: "Source note")
    note_block = Block.create!(
      workspace: workspace,
      page: source_page,
      created_by: owner,
      block_type: "paragraph",
      content_json: {
        "type" => "doc",
        "content" => [
          {
            "type" => "paragraph",
            "content" => [ { "type" => "text", "text" => "Client brief" } ]
          }
        ]
      }
    )
    grid_block = Block.create!(
      workspace: workspace,
      page: source_page,
      created_by: owner,
      block_type: "paragraph",
      content_json: {
        "type" => "doc",
        "content" => [
          {
            "type" => "paragraph",
            "content" => [ { "type" => "text", "text" => "Project board" } ]
          }
        ]
      }
    )
    sign_in owner

    expect do
      post command_page_block_path(workspace_slug: workspace.slug, page_id: source_page.id, id: note_block.id),
           params: { block_command: { command: "create_linked_nota" } }
    end.to change(Page, :count).by(1)

    linked_note = workspace.pages.where.not(id: source_page.id).order(:created_at).last
    expect(response).to redirect_to(
      page_path(
        workspace_slug: workspace.slug,
        id: source_page.id,
        split_page_id: linked_note.id,
        split_source: "block",
        anchor: "block_#{note_block.id}"
      )
    )
    expect(note_block.reload.block_type).to eq("paragraph")
    expect(note_block.content_json.dig("content", 0, "content", 0, "text")).to eq(linked_note.title)
    expect(note_block.content_json.dig("content", 0, "content", 0, "marks", 0, "attrs", "href")).to eq(
      page_path(workspace_slug: workspace.slug, id: source_page.id, split_page_id: linked_note.id, split_source: "block")
    )
    expect(note_block.content_json.dig("content", 0, "content", 0, "marks", 0, "attrs", "target")).to eq("_self")
    expect(PageLink.where(source_block: note_block, target_page: linked_note)).to exist

    get page_path(workspace_slug: workspace.slug, id: source_page.id, split_page_id: linked_note.id, split_source: "block")

    expect(response).to have_http_status(:ok)
    note_split_html = Nokogiri::HTML(response.body)
    expect(note_split_html.at_css(".notae-db-split-frame")["src"]).to eq(
      page_path(workspace_slug: workspace.slug, id: linked_note.id, embedded: "1")
    )

    get page_path(workspace_slug: workspace.slug, id: linked_note.id)

    expect(response.body).to include("data-backlink-source=\"#{source_page.id}\"")
    expect(response.body).to include(source_page.title)

    expect do
      post command_page_block_path(workspace_slug: workspace.slug, page_id: source_page.id, id: grid_block.id),
           params: { block_command: { command: "create_linked_grid" } }
    end.to change(Database, :count).by(1).and change(Page, :count).by(1)

    linked_grid = workspace.databases.order(:created_at).last
    linked_grid_page = linked_grid.linked_page
    expect(linked_grid_page).to be_present
    expect(response).to redirect_to(
      page_path(
        workspace_slug: workspace.slug,
        id: source_page.id,
        split_page_id: linked_grid_page.id,
        split_source: "block",
        anchor: "block_#{grid_block.id}"
      )
    )
    expect(grid_block.reload.content_json.dig("content", 0, "content", 0, "text")).to eq(linked_grid.name)
    expect(grid_block.content_json.dig("content", 0, "content", 0, "marks", 0, "attrs", "href")).to eq(
      page_path(workspace_slug: workspace.slug, id: source_page.id, split_page_id: linked_grid_page.id, split_source: "block")
    )
    expect(grid_block.content_json.dig("content", 0, "content", 0, "marks", 0, "attrs", "target")).to eq("_self")
    expect(PageLink.where(source_block: grid_block, target_page: linked_grid_page)).to exist

    get page_path(workspace_slug: workspace.slug, id: source_page.id, split_page_id: linked_grid_page.id, split_source: "block")

    expect(response).to have_http_status(:ok)
    grid_split_html = Nokogiri::HTML(response.body)
    expect(grid_split_html.at_css(".notae-db-split-frame")["src"]).to eq(
      database_path(workspace_slug: workspace.slug, id: linked_grid.id, embedded: "1")
    )

    get database_path(workspace_slug: workspace.slug, id: linked_grid.id)

    expect(response.body).to include("data-backlink-source=\"#{source_page.id}\"")
    expect(response.body).to include(source_page.title)
  end

  it "links existing notas and grids from block actions without creating standalone records" do
    owner = User.create!(email: "blocks-linked-existing-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Linked existing blocks", slug: "linked-existing-blocks")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    source_page = Page.create!(workspace: workspace, created_by: owner, title: "Source note")
    existing_note = Page.create!(workspace: workspace, created_by: owner, title: "Existing note")
    existing_grid = Database.create!(workspace: workspace, name: "Existing grid", created_by: owner)
    existing_grid_page = Databases::EnsureLinkedPageService.call(database: existing_grid, actor: owner)
    note_block = Block.create!(workspace: workspace, page: source_page, created_by: owner, block_type: "paragraph")
    grid_block = Block.create!(workspace: workspace, page: source_page, created_by: owner, block_type: "paragraph")
    sign_in owner

    expect do
      post command_page_block_path(workspace_slug: workspace.slug, page_id: source_page.id, id: note_block.id),
           params: { block_command: { command: "link_existing_nota", target_page_id: existing_note.id } }
    end.not_to change(Page, :count)

    expect(response).to redirect_to(
      page_path(
        workspace_slug: workspace.slug,
        id: source_page.id,
        split_page_id: existing_note.id,
        split_source: "block",
        anchor: "block_#{note_block.id}"
      )
    )
    expect(note_block.reload.content_json.dig("content", 0, "content", 0, "text")).to eq(existing_note.title)
    expect(note_block.content_json.dig("content", 0, "content", 0, "marks", 0, "attrs", "href")).to eq(
      page_path(workspace_slug: workspace.slug, id: source_page.id, split_page_id: existing_note.id, split_source: "block")
    )
    expect(note_block.content_json.dig("content", 0, "content", 0, "marks", 0, "attrs", "target")).to eq("_self")
    expect(PageLink.where(source_block: note_block, target_page: existing_note)).to exist

    expect do
      post command_page_block_path(workspace_slug: workspace.slug, page_id: source_page.id, id: grid_block.id),
           params: { block_command: { command: "link_existing_grid", target_database_id: existing_grid.id } }
    end.not_to change(Database, :count)

    expect(response).to redirect_to(
      page_path(
        workspace_slug: workspace.slug,
        id: source_page.id,
        split_page_id: existing_grid_page.id,
        split_source: "block",
        anchor: "block_#{grid_block.id}"
      )
    )
    expect(grid_block.reload.content_json.dig("content", 0, "content", 0, "text")).to eq(existing_grid.name)
    expect(grid_block.content_json.dig("content", 0, "content", 0, "marks", 0, "attrs", "href")).to eq(
      page_path(workspace_slug: workspace.slug, id: source_page.id, split_page_id: existing_grid_page.id, split_source: "block")
    )
    expect(grid_block.content_json.dig("content", 0, "content", 0, "marks", 0, "attrs", "target")).to eq("_self")
    expect(PageLink.where(source_block: grid_block, target_page: existing_grid_page)).to exist

    get page_path(workspace_slug: workspace.slug, id: source_page.id, split_page_id: existing_grid_page.id, split_source: "block")

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    expect(html.at_css(".notae-db-split-frame")["src"]).to eq(
      database_path(workspace_slug: workspace.slug, id: existing_grid.id, embedded: "1")
    )
  end

  it "shows unlink for linked block actions and removes linked nota/grid targets" do
    owner = User.create!(email: "blocks-unlink-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Linked unlink blocks", slug: "linked-unlink-blocks")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    source_page = Page.create!(workspace: workspace, created_by: owner, title: "Source note")
    existing_grid = Database.create!(workspace: workspace, name: "Existing grid", created_by: owner)
    existing_grid_page = Databases::EnsureLinkedPageService.call(database: existing_grid, actor: owner)
    block = Block.create!(workspace: workspace, page: source_page, created_by: owner, block_type: "paragraph")
    sign_in owner

    post command_page_block_path(workspace_slug: workspace.slug, page_id: source_page.id, id: block.id),
         params: { block_command: { command: "link_existing_grid", target_database_id: existing_grid.id } }

    expect(response).to redirect_to(
      page_path(
        workspace_slug: workspace.slug,
        id: source_page.id,
        split_page_id: existing_grid_page.id,
        split_source: "block",
        anchor: "block_#{block.id}"
      )
    )

    get panel_page_block_path(workspace_slug: workspace.slug, page_id: source_page.id, id: block.id)

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    unlink_form = document.css("form").find do |form|
      form.at_css('input[name="block_command[command]"][value="unlink_linked_document"]')
    end

    expect(unlink_form).to be_present
    expect(unlink_form.at_css(".notae-menu-item-label")&.text&.strip).to eq("Unlink Grid")

    post command_page_block_path(
      workspace_slug: workspace.slug,
      page_id: source_page.id,
      id: block.id,
      split_page_id: existing_grid_page.id,
      split_source: "block"
    ), params: { block_command: { command: "unlink_linked_document" } }

    expect(response).to redirect_to(
      page_path(workspace_slug: workspace.slug, id: source_page.id, anchor: "block_#{block.id}")
    )

    expect(block.reload.content_json.dig("content", 0, "content", 0, "text")).to eq(existing_grid.name)
    expect(block.content_json.dig("content", 0, "content", 0, "marks")).to be_nil
    expect(PageLink.where(source_block: block, target_page: existing_grid_page)).to be_empty
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

  it "renders expandable pickers for linking existing notas and grids from the block menu" do
    owner = User.create!(email: "blocks-picker-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Block picker workspace", slug: "block-picker-workspace")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    source_page = Page.create!(workspace: workspace, created_by: owner, title: "Source page")
    Page.create!(workspace: workspace, created_by: owner, title: "Existing note")
    Database.create!(workspace: workspace, name: "Existing grid", created_by: owner)
    block = Block.create!(workspace: workspace, page: source_page, created_by: owner, block_type: "paragraph")
    sign_in owner

    get panel_page_block_path(workspace_slug: workspace.slug, page_id: source_page.id, id: block.id)

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    picker_rows = document.css(".notae-block-menu-picker-row")
    expect(picker_rows.size).to eq(2)

    picker_forms = document.css("form.notae-block-menu-picker-form")
    expect(picker_forms.size).to eq(3)

    note_form = picker_forms.find do |form|
      form.at_css('input[name="block_command[command]"][value="link_existing_nota"]')
    end
    grid_form = picker_forms.find do |form|
      form.at_css('input[name="block_command[command]"][value="link_existing_grid"]')
    end
    move_form = picker_forms.find do |form|
      form.at_css('input[name="block_command[command]"][value="move_to"]')
    end

    expect(note_form.at_css('button[data-action="block-tools#togglePicker"]')).to be_present
    expect(note_form["data-controller"]).to be_blank
    expect(note_form.parent.at_css('.notae-block-menu-picker[hidden]')).to be_present
    expect(note_form.parent["data-controller"]).to eq("document-picker")
    expect(note_form.parent.at_css('input[data-document-picker-target="hiddenInput"]')).to be_present
    expect(note_form.parent.at_css('input[data-document-picker-target="searchInput"]')).to be_present
    expect(note_form.parent.at_css('.notae-block-menu-inline-form .notae-menu-item-label')&.text).to eq("Create linked Nota")

    expect(grid_form.at_css('button[data-action="block-tools#togglePicker"]')).to be_present
    expect(grid_form["data-controller"]).to be_blank
    expect(grid_form.parent.at_css('.notae-block-menu-picker[hidden]')).to be_present
    expect(grid_form.parent["data-controller"]).to eq("document-picker")
    expect(grid_form.parent.at_css('input[data-document-picker-target="hiddenInput"]')).to be_present
    expect(grid_form.parent.at_css('input[data-document-picker-target="searchInput"]')).to be_present
    expect(grid_form.parent.at_css('.notae-block-menu-inline-form .notae-menu-item-label')&.text).to eq("Create linked Grid")

    expect(move_form["data-controller"]).to eq("document-picker")
    expect(move_form.at_css('input[data-document-picker-target="hiddenInput"]')).to be_present
    expect(move_form.at_css('input[data-document-picker-target="searchInput"]')).to be_present
  end

  it "keeps linked nota and grid picker rows inline while letting the chooser span the full menu width" do
    stylesheet = Rails.root.join("app/assets/stylesheets/application.css").read

    expect(stylesheet).to include(".notae-block-menu-picker-row {\n  grid-column: 1 / -1;\n  display: grid;\n  grid-template-columns: repeat(2, minmax(0, 1fr));")
    expect(stylesheet).to include(".notae-block-menu-picker-row .notae-block-menu-picker {\n  grid-column: 1 / -1;")
  end
end
