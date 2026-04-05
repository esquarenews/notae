require "rails_helper"

RSpec.describe "WorkspaceDocumentTargets", type: :request do
  it "returns workspace-scoped note, page, and grid results for lazy pickers" do
    owner = User.create!(email: "document-targets-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Document targets", slug: "document-targets")
    other_workspace = Workspace.create!(name: "Other targets", slug: "other-targets")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: other_workspace, user: owner, role: :owner)

    current_page = Page.create!(workspace: workspace, created_by: owner, title: "Current page")
    note_page = Page.create!(workspace: workspace, created_by: owner, title: "Existing note")
    grid_shell_page = Page.create!(workspace: workspace, created_by: owner, title: "Existing grid shell")
    database = Database.create!(workspace: workspace, created_by: owner, name: "Existing grid", linked_page: grid_shell_page)
    Page.create!(workspace: other_workspace, created_by: owner, title: "Remote note")
    Database.create!(workspace: other_workspace, created_by: owner, name: "Remote grid")
    sign_in owner

    get workspace_document_targets_path(workspace_slug: workspace.slug, kind: "note", exclude_page_id: current_page.id, q: "Existing")

    expect(response).to have_http_status(:ok)
    note_results = JSON.parse(response.body).dig("data", "results")
    expect(note_results).to include(include("id" => note_page.id, "label" => "Existing note"))
    expect(note_results).not_to include(include("id" => current_page.id))
    expect(note_results).not_to include(include("id" => grid_shell_page.id))

    get workspace_document_targets_path(workspace_slug: workspace.slug, kind: "page", q: "Current")

    expect(response).to have_http_status(:ok)
    page_results = JSON.parse(response.body).dig("data", "results")
    expect(page_results).to include(include("id" => current_page.id, "label" => "Current page"))

    get workspace_document_targets_path(workspace_slug: workspace.slug, kind: "grid", q: "Existing")

    expect(response).to have_http_status(:ok)
    grid_results = JSON.parse(response.body).dig("data", "results")
    expect(grid_results.length).to eq(1)
    expect(grid_results).to include(include("id" => database.id, "label" => "Existing grid"))
  end
end
