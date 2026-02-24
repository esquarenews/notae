require "rails_helper"

RSpec.describe "Block collaboration broadcasts", type: :request do
  it "broadcasts block updates to page viewers" do
    owner = User.create!(email: "broadcast-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Broadcast workspace", slug: "broadcast-workspace")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Broadcast page")
    block = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "paragraph")
    sign_in owner

    allow(ActionCable.server).to receive(:broadcast)

    patch page_block_path(workspace_slug: workspace.slug, page_id: page.id, id: block.id),
          params: {
            block: {
              block_type: "heading_1",
              content_json: {
                type: "doc",
                content: [ { type: "heading", attrs: { level: 1 }, content: [ { type: "text", text: "Realtime" } ] } ]
              }
            }
          },
          as: :json

    expect(response).to have_http_status(:ok)
    expect(ActionCable.server).to have_received(:broadcast).with(
      "page:#{page.id}:collaboration",
      hash_including(
        type: "block_updated",
        actor_id: owner.id,
        block: hash_including(
          id: block.id,
          block_type: "heading_1"
        )
      )
    )
  end
end
