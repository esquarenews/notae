require "rails_helper"

RSpec.describe Pages::MarkdownExportService, type: :service do
  it "renders headings, lists, links, and attachment references" do
    owner = User.create!(email: "markdown-export-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Markdown export", slug: "markdown-export")
    page = Page.create!(workspace: workspace, created_by: owner, title: "Product plan")
    Block.create!(
      workspace: workspace,
      page: page,
      created_by: owner,
      block_type: "paragraph",
      content_json: {
        "type" => "doc",
        "content" => [
          { "type" => "heading", "attrs" => { "level" => 2 }, "content" => [ { "type" => "text", "text" => "Sprint plan" } ] },
          {
            "type" => "bulletList",
            "content" => [
              { "type" => "listItem", "content" => [ { "type" => "paragraph", "content" => [ { "type" => "text", "text" => "Ship board view" } ] } ] },
              {
                "type" => "listItem",
                "content" => [
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
            ]
          }
        ]
      }
    )
    file_block = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "file")
    Tempfile.create([ "markdown-export", ".txt" ]) do |file|
      file.write("attachment body")
      file.rewind
      file_block.asset.attach(io: file, filename: "notes.txt", content_type: "text/plain")
    end

    result = described_class.call(page: page)

    expect(result.markdown).to include("# Product plan")
    expect(result.markdown).to include("## Sprint plan")
    expect(result.markdown).to include("- Ship board view")
    expect(result.markdown).to include("[spec](https://example.com/spec)")
    expect(result.markdown).to include("## Attachments")
    expect(result.attachments.size).to eq(1)
    expect(result.attachments.first.relative_path).to start_with("attachments/")
    expect(result.markdown).to include("(#{result.attachments.first.relative_path})")
  end
end
