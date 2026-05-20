require "rails_helper"

RSpec.describe "Backlinks", type: :request do
  def backlink_href_for(response_body, source:)
    document = Nokogiri::HTML.parse(response_body)
    document.at_css(%([data-backlink-source="#{source}"]))&.[]("href")
  end

  def local_document_timestamp(timestamp, user)
    timestamp.in_time_zone(user.time_zone).strftime("%a %-d %b %Y %H:%M %Z")
  end

  it "detects links from block content and renders backlinks on target pages" do
    owner = User.create!(email: "backlink-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Backlinks", slug: "backlinks")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    source_page = Page.create!(workspace: workspace, created_by: owner, title: "Source")
    target_page = Page.create!(workspace: workspace, created_by: owner, title: "Target")

    block = Block.create!(
      workspace: workspace,
      page: source_page,
      created_by: owner,
      block_type: "paragraph",
      content_json: {
        type: "doc",
        content: [ { type: "paragraph", content: [ { type: "text", text: "See [[Target]] for details." } ] } ]
      }
    )

    expect(PageLink.where(source_block: block, target_page: target_page)).to exist

    sign_in owner
    get page_path(workspace_slug: workspace.slug, id: target_page.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Backlinks")
    expect(response.body).to include("data-backlink-source=\"#{source_page.id}\"")
  end

  it "renders local originated and edited timestamps above page backlinks" do
    owner = User.create!(
      email: "backlink-page-timestamps@example.com",
      password: "password123",
      time_zone: "Australia/Melbourne"
    )
    workspace = Workspace.create!(name: "Page timestamps", slug: "page-timestamps")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Timestamped note")
    page.update_columns(
      created_at: Time.utc(2026, 5, 20, 23, 15),
      updated_at: Time.utc(2026, 5, 21, 1, 45)
    )
    sign_in owner

    get page_path(workspace_slug: workspace.slug, id: page.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Originated: #{local_document_timestamp(page.reload.created_at, owner)}")
    expect(response.body).to include("Last edited: #{local_document_timestamp(page.updated_at, owner)}")

    document = Nokogiri::HTML.parse(response.body)
    timestamp_block = document.at_css(".notae-doc-backlinks .notae-doc-timestamps")
    expect(timestamp_block).to be_present
    expect(timestamp_block.ancestors(".notae-doc-backlinks")).to be_present
  end

  it "renders local originated and edited timestamps above grid backlinks" do
    owner = User.create!(
      email: "backlink-grid-timestamps@example.com",
      password: "password123",
      time_zone: "Australia/Melbourne"
    )
    workspace = Workspace.create!(name: "Grid timestamps", slug: "grid-timestamps")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Timestamped grid", created_by: owner)
    database.update_columns(
      created_at: Time.utc(2026, 5, 19, 22, 30),
      updated_at: Time.utc(2026, 5, 21, 2, 5)
    )
    sign_in owner

    get database_path(workspace_slug: workspace.slug, id: database.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Originated: #{local_document_timestamp(database.reload.created_at, owner)}")
    expect(response.body).to include("Last edited: #{local_document_timestamp(database.updated_at, owner)}")

    document = Nokogiri::HTML.parse(response.body)
    timestamp_block = document.at_css(".notae-doc-backlinks .notae-doc-timestamps")
    expect(timestamp_block).to be_present
    expect(timestamp_block.ancestors(".notae-doc-backlinks")).to be_present
  end

  it "removes backlinks when links are removed from block content" do
    owner = User.create!(email: "backlink-owner-2@example.com", password: "password123")
    workspace = Workspace.create!(name: "Backlinks 2", slug: "backlinks-2")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    source_page = Page.create!(workspace: workspace, created_by: owner, title: "Source 2")
    target_page = Page.create!(workspace: workspace, created_by: owner, title: "Target 2")

    block = Block.create!(
      workspace: workspace,
      page: source_page,
      created_by: owner,
      block_type: "paragraph",
      content_json: {
        type: "doc",
        content: [ { type: "paragraph", content: [ { type: "text", text: "See [[Target 2]]" } ] } ]
      }
    )
    expect(PageLink.where(source_block: block, target_page: target_page)).to exist

    block.update!(
      content_json: {
        type: "doc",
        content: [ { type: "paragraph", content: [ { type: "text", text: "No links now" } ] } ]
      }
    )

    sign_in owner
    get page_path(workspace_slug: workspace.slug, id: target_page.id)

    expect(response.body).not_to include("data-backlink-source=\"#{source_page.id}\"")
  end

  it "renders grid backlinks for notes linked from grid rows" do
    owner = User.create!(email: "backlink-grid-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Grid backlinks", slug: "grid-backlinks")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Tasks grid", created_by: owner)
    Databases::EnsureLinkedPageService.call(database:, actor: owner)
    linked_note = Page.create!(workspace: workspace, created_by: owner, title: "Follow-up note")
    DbRow.create!(workspace: workspace, database: database, title: "Linked row", linked_page: linked_note)

    sign_in owner
    get page_path(workspace_slug: workspace.slug, id: linked_note.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Backlinks")
    expect(response.body).to include("data-backlink-source=\"database:#{database.id}\"")
    expect(response.body).to include(database.name)
    expect(response.body).to include(database_path(workspace_slug: workspace.slug, id: database.id))
  end

  it "keeps page backlinks embedded when rendered in a split pane" do
    owner = User.create!(email: "backlink-embedded-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Embedded backlinks", slug: "embedded-backlinks")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    source_page = Page.create!(workspace: workspace, created_by: owner, title: "Embedded source")
    target_page = Page.create!(workspace: workspace, created_by: owner, title: "Embedded target")

    Block.create!(
      workspace: workspace,
      page: source_page,
      created_by: owner,
      block_type: "paragraph",
      content_json: {
        type: "doc",
        content: [ { type: "paragraph", content: [ { type: "text", text: "See [[Embedded target]]" } ] } ]
      }
    )

    sign_in owner
    get page_path(workspace_slug: workspace.slug, id: target_page.id, embedded: 1)

    expect(response).to have_http_status(:ok)
    expect(backlink_href_for(response.body, source: source_page.id)).to eq(
      page_path(workspace_slug: workspace.slug, id: source_page.id, embedded: "1")
    )
  end

  it "keeps grid backlinks embedded when rendered in a split pane" do
    owner = User.create!(email: "backlink-grid-embedded-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Embedded grid backlinks", slug: "embedded-grid-backlinks")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Embedded grid", created_by: owner)
    Databases::EnsureLinkedPageService.call(database:, actor: owner)
    linked_note = Page.create!(workspace: workspace, created_by: owner, title: "Embedded grid note")
    DbRow.create!(workspace: workspace, database: database, title: "Linked row", linked_page: linked_note)

    sign_in owner
    get page_path(workspace_slug: workspace.slug, id: linked_note.id, embedded: 1)

    expect(response).to have_http_status(:ok)
    expect(backlink_href_for(response.body, source: "database:#{database.id}")).to eq(
      database_path(workspace_slug: workspace.slug, id: database.id, embedded: "1")
    )
  end
end
