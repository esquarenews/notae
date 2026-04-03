require "rails_helper"

RSpec.describe Blocks::MarkdownExportService, type: :service do
  it "renders a single block as markdown without page-level wrappers" do
    owner = User.create!(email: "block-markdown-export-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Block markdown export", slug: "block-markdown-export")
    page = Page.create!(workspace: workspace, created_by: owner, title: "Product plan")
    block = Block.create!(
      workspace: workspace,
      page: page,
      created_by: owner,
      block_type: "paragraph",
      content_json: {
        "type" => "doc",
        "content" => [
          { "type" => "heading", "attrs" => { "level" => 2 }, "content" => [ { "type" => "text", "text" => "Sprint plan" } ] },
          {
            "type" => "paragraph",
            "content" => [
              { "type" => "text", "text" => "Review " },
              {
                "type" => "text",
                "text" => "spec",
                "marks" => [ { "type" => "link", "attrs" => { "href" => "https://example.com/spec" } } ]
              }
            ]
          }
        ]
      }
    )

    result = described_class.call(block: block)

    expect(result).to include("## Sprint plan")
    expect(result).to include("[spec](https://example.com/spec)")
    expect(result).not_to include("# Product plan")
  end
end
