require "rails_helper"
require "zip"
require "stringio"

RSpec.describe PageExports::BuildZipJob, type: :job do
  it "generates a zip archive containing markdown and attachments" do
    owner = User.create!(email: "zip-export-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Zip export workspace", slug: "zip-export-workspace")
    page = Page.create!(workspace: workspace, created_by: owner, title: "Release notes")
    Block.create!(
      workspace: workspace,
      page: page,
      created_by: owner,
      block_type: "paragraph",
      content_json: {
        "type" => "doc",
        "content" => [
          { "type" => "paragraph", "content" => [ { "type" => "text", "text" => "Ship the release." } ] }
        ]
      }
    )
    file_block = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "file")
    Tempfile.create([ "zip-export", ".txt" ]) do |file|
      file.write("file payload")
      file.rewind
      file_block.asset.attach(io: file, filename: "release.txt", content_type: "text/plain")
    end
    page_export = PageExport.create!(workspace: workspace, page: page, requested_by: owner)

    described_class.perform_now(page_export.id)
    page_export.reload

    expect(page_export.status).to eq("ready")
    expect(page_export.archive_file).to be_attached
    expect(page_export.completed_at).to be_present

    entries = {}
    Zip::InputStream.open(StringIO.new(page_export.archive_file.download)) do |stream|
      while (entry = stream.get_next_entry)
        entries[entry.name] = stream.read
      end
    end

    markdown_entry = entries.keys.find { |name| name.end_with?(".md") }
    attachment_entry = entries.keys.find { |name| name.start_with?("attachments/") }

    expect(markdown_entry).to be_present
    expect(entries[markdown_entry]).to include("# Release notes")
    expect(attachment_entry).to be_present
    expect(entries[attachment_entry]).to eq("file payload")
  end
end
