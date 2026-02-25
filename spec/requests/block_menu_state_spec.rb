require "rails_helper"

RSpec.describe "Block menu state", type: :request do
  it "renders active turn-into and color menu states for the current block" do
    owner = User.create!(email: "block-menu-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Menu state", slug: "menu-state")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Menu state page")
    Block.create!(
      workspace: workspace,
      page: page,
      created_by: owner,
      block_type: "heading_1",
      content_json: {
        "type" => "doc",
        "notae_color" => "blue",
        "content" => [
          {
            "type" => "heading",
            "attrs" => { "level" => 1 },
            "content" => [ { "type" => "text", "text" => "Heading" } ]
          }
        ]
      }
    )
    sign_in owner

    get page_path(workspace_slug: workspace.slug, id: page.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("notae-doc-block is-type-heading-1")
    expect(response.body).to match(
      /notae-block-menu-item is-active[^>]*>\s*<span class="notae-menu-item-icon">H1<\/span>\s*<span class="notae-menu-item-label">Heading 1<\/span>/m
    )
    expect(response.body).to match(
      /notae-block-menu-item is-active[^>]*>\s*<span class="notae-menu-color-dot is-blue"><\/span>\s*<span class="notae-menu-item-label">Blue<\/span>/m
    )
  end

  it "toggles an active turn-into or color option off when selected again" do
    owner = User.create!(email: "block-menu-toggle-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Menu toggle", slug: "menu-toggle")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Menu toggle page")
    block = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "heading_2")
    sign_in owner

    post command_page_block_path(workspace_slug: workspace.slug, page_id: page.id, id: block.id),
         params: { block_command: { command: "turn_into", target: "heading_2" } }

    expect(block.reload.block_type).to eq("paragraph")

    post command_page_block_path(workspace_slug: workspace.slug, page_id: page.id, id: block.id),
         params: { block_command: { command: "color", color: "green" } }

    expect(block.reload.color).to eq("green")

    post command_page_block_path(workspace_slug: workspace.slug, page_id: page.id, id: block.id),
         params: { block_command: { command: "color", color: "green" } }

    expect(block.reload.color).to eq("default")
  end
end
