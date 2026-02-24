require "rails_helper"

RSpec.describe Api::V1::Blocks::UpdateService, type: :service do
  it "updates json content and block type independently of controller wiring" do
    owner = User.create!(email: "api-block-service-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "API Block Service", slug: "api-block-service")
    page = Page.create!(workspace: workspace, created_by: owner, title: "Block service page")
    block = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "paragraph")

    described_class.call(
      block: block,
      attributes: {
        block_type: "heading_2",
        content_json: {
          "type" => "doc",
          "content" => [
            {
              "type" => "heading",
              "attrs" => { "level" => 2 },
              "content" => [ { "type" => "text", "text" => "Service update" } ]
            }
          ]
        }
      }
    )

    expect(block.reload.block_type).to eq("heading_2")
    expect(block.content_json.dig("content", 0, "type")).to eq("heading")
  end
end
