require "rails_helper"

RSpec.describe "Backlinks", type: :request do
  def backlink_href_for(response_body, source:)
    document = Nokogiri::HTML.parse(response_body)
    document.at_css(%([data-backlink-source="#{source}"]))&.[]("href")
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
