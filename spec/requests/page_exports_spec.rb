require "rails_helper"

RSpec.describe "Page exports", type: :request do
  include ActiveJob::TestHelper

  def extract_pdf_text(data)
    PDF::Reader.new(StringIO.new(data)).pages.map(&:text).join("\n")
  end

  it "exports markdown with headings, lists, links, and attachment references" do
    owner = User.create!(email: "page-exports-md-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Page export markdown", slug: "page-export-markdown")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Export page")
    Block.create!(
      workspace: workspace,
      page: page,
      created_by: owner,
      block_type: "paragraph",
      content_json: {
        "type" => "doc",
        "content" => [
          { "type" => "heading", "attrs" => { "level" => 2 }, "content" => [ { "type" => "text", "text" => "Backlog" } ] },
          { "type" => "bulletList", "content" => [ { "type" => "listItem", "content" => [ { "type" => "paragraph", "content" => [ { "type" => "text", "text" => "First item" } ] } ] } ] },
          {
            "type" => "paragraph",
            "content" => [
              { "type" => "text", "text" => "Read the " },
              { "type" => "text", "text" => "docs", "marks" => [ { "type" => "link", "attrs" => { "href" => "https://example.com/docs" } } ] }
            ]
          }
        ]
      }
    )
    file_block = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "file")
    Tempfile.create([ "page-exports-md", ".txt" ]) do |file|
      file.write("md attachment")
      file.rewind
      file_block.asset.attach(io: file, filename: "reference.txt", content_type: "text/plain")
    end
    sign_in owner

    get export_markdown_page_path(workspace_slug: workspace.slug, id: page.id)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/markdown")
    expect(response.body).to include("## Backlog")
    expect(response.body).to include("- First item")
    expect(response.body).to include("[docs](https://example.com/docs)")
    expect(response.body).to include("## Attachments")
    expect(response.body).to include("attachments/")
  end

  it "exports pdf with page title, content, and attachments" do
    owner = User.create!(email: "page-exports-pdf-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Page export pdf", slug: "page-export-pdf")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Export page")
    Block.create!(
      workspace: workspace,
      page: page,
      created_by: owner,
      block_type: "paragraph",
      content_json: {
        "type" => "doc",
        "content" => [
          { "type" => "heading", "attrs" => { "level" => 2 }, "content" => [ { "type" => "text", "text" => "Backlog" } ] },
          { "type" => "paragraph", "content" => [ { "type" => "text", "text" => "First item" } ] }
        ]
      }
    )
    file_block = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "file")
    Tempfile.create([ "page-exports-pdf", ".txt" ]) do |file|
      file.write("pdf attachment")
      file.rewind
      file_block.asset.attach(io: file, filename: "reference.txt", content_type: "text/plain")
    end
    sign_in owner

    get export_pdf_page_path(workspace_slug: workspace.slug, id: page.id)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/pdf")
    expect(response.headers["Content-Disposition"]).to include(".pdf")

    extracted_text = extract_pdf_text(response.body)
    expect(extracted_text).to include("Export page")
    expect(extracted_text).to include("Backlog")
    expect(extracted_text).to include("First item")
    expect(extracted_text).to include("reference.txt")
  end

  it "queues a zip export job and expires download links" do
    owner = User.create!(email: "page-exports-zip-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Page export zip", slug: "page-export-zip")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Zip page")
    file_block = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "file")
    Tempfile.create([ "page-exports-zip", ".txt" ]) do |file|
      file.write("zip attachment")
      file.rewind
      file_block.asset.attach(io: file, filename: "payload.txt", content_type: "text/plain")
    end
    sign_in owner

    expect do
      post export_zip_page_path(workspace_slug: workspace.slug, id: page.id)
    end.to have_enqueued_job(PageExports::BuildZipJob)
    expect(response).to redirect_to(page_path(workspace_slug: workspace.slug, id: page.id))

    page_export = PageExport.recent_first.first
    expect(page_export.status).to eq("pending")

    PageExports::BuildZipJob.perform_now(page_export.id)
    page_export.reload
    expect(page_export).to be_downloadable

    get workspace_export_path(workspace_slug: workspace.slug, token: page_export.token)

    expect(response).to have_http_status(:ok)
    expect(response.headers["Content-Disposition"]).to include(".zip")

    page_export.update!(expires_at: 1.minute.ago)

    get workspace_export_path(workspace_slug: workspace.slug, token: page_export.token)

    expect(response).to have_http_status(:not_found)
  end

  it "marks exports failed when the background queue is unavailable" do
    owner = User.create!(email: "page-exports-queue-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Page export queue", slug: "page-export-queue")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Queue page")
    sign_in owner

    allow(PageExports::BuildZipJob).to receive(:perform_later).and_raise(StandardError, "redis unavailable")

    post export_zip_page_path(workspace_slug: workspace.slug, id: page.id)

    expect(response).to redirect_to(page_path(workspace_slug: workspace.slug, id: page.id))
    page_export = PageExport.recent_first.first
    expect(page_export.status).to eq("failed")
    expect(page_export.error_message).to include("Queue unavailable")
  end

  it "enforces workspace permissions for markdown and zip download endpoints" do
    owner = User.create!(email: "page-exports-policy-owner@example.com", password: "password123")
    outsider = User.create!(email: "page-exports-policy-outsider@example.com", password: "password123")
    workspace = Workspace.create!(name: "Page export policy", slug: "page-export-policy")
    other_workspace = Workspace.create!(name: "Page export other", slug: "page-export-other")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: other_workspace, user: outsider, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Protected export")
    page_export = PageExport.create!(workspace: workspace, page: page, requested_by: owner, status: :ready, expires_at: 20.minutes.from_now)
    page_export.archive_file.attach(io: StringIO.new("zip"), filename: "protected.zip", content_type: "application/zip")
    sign_in outsider

    get export_markdown_page_path(workspace_slug: workspace.slug, id: page.id)
    expect([ 302, 404 ]).to include(response.status)

    get export_pdf_page_path(workspace_slug: workspace.slug, id: page.id)
    expect([ 302, 404 ]).to include(response.status)

    get workspace_export_path(workspace_slug: workspace.slug, token: page_export.token)
    expect([ 302, 404 ]).to include(response.status)
  end
end
