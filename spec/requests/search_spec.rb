require "rails_helper"

RSpec.describe "Search", type: :request do
  it "returns highlighted workspace-scoped results across pages, blocks, and rows" do
    user = User.create!(email: "search-user@example.com", password: "password123")
    workspace = Workspace.create!(name: "Searchable", slug: "searchable")
    other_workspace = Workspace.create!(name: "Other", slug: "other-search")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    Membership.create!(workspace: other_workspace, user: user, role: :owner)

    page = Page.create!(workspace: workspace, created_by: user, title: "Alpha Planning")
    Block.create!(
      workspace: workspace,
      page: page,
      created_by: user,
      block_type: "paragraph",
      content_json: {
        type: "doc",
        content: [ { type: "paragraph", content: [ { type: "text", text: "alpha roadmap block" } ] } ]
      }
    )

    database = Database.create!(workspace: workspace, name: "Tasks")
    DbRow.create!(workspace: workspace, database: database, title: "Alpha row", data_json: { notes: "track alpha launch" })

    Page.create!(workspace: other_workspace, created_by: user, title: "Alpha Secret")

    sign_in user
    get workspace_search_path(workspace_slug: workspace.slug), params: { q: "alpha" }

    expect(response).to have_http_status(:ok)
    expect(response.headers["X-Notae-Perf-Action"]).to eq("SearchesController#index")
    expect(response.headers["X-Notae-Perf-Sql-Queries"]).to be_present
    expect(response.headers["X-Notae-Perf-Sql-Queries"].to_i).to be <= Notae::RequestPerformanceStore.budget_for(action: "SearchesController#index").fetch(:sql_queries)
    expect(response.body).to include("notae-utility-page")
    expect(response.body).to include("notae-utility-search-form")
    expect(response.body).to include("notae-utility-result-item")
    expect(response.body).to include("Page")
    expect(response.body).to include("Block")
    expect(response.body).to include("Row")
    expect(response.body).to match(/<mark>alpha<\/mark>/i)
    expect(response.body).not_to include("Alpha Secret")
  end

  it "blocks search access for users outside the workspace" do
    owner = User.create!(email: "search-owner@example.com", password: "password123")
    outsider = User.create!(email: "search-outsider@example.com", password: "password123")
    workspace = Workspace.create!(name: "Private Search", slug: "private-search")
    Membership.create!(workspace: workspace, user: owner, role: :owner)

    sign_in outsider
    get workspace_search_path(workspace_slug: workspace.slug), params: { q: "private" }

    expect(response).to have_http_status(:not_found)
  end

  it "renders an AI summary when OpenAI key is configured" do
    user = User.create!(email: "search-ai@example.com", password: "password123", openai_api_key: "sk-test")
    workspace = Workspace.create!(name: "AI Searchable", slug: "ai-searchable")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    Page.create!(workspace: workspace, created_by: user, title: "Launch Brief")

    allow(Openai::EmbeddingsClient).to receive(:embed_with_usage).and_return(
      { embedding: [], usage: { prompt_tokens: 10, completion_tokens: 0, total_tokens: 10 } }
    )
    allow(Openai::ResponsesClient).to receive(:generate_text_with_usage).and_return(
      { text: "Launch brief summary [1].", usage: { prompt_tokens: 120, completion_tokens: 18, total_tokens: 138 } }
    )

    sign_in user
    get workspace_search_path(workspace_slug: workspace.slug), params: { q: "launch" }

    expect(response).to have_http_status(:ok)
    expect(response.headers["X-Notae-Perf-Sql-Queries"].to_i).to be <= Notae::RequestPerformanceStore.budget_for(action: "SearchesController#index").fetch(:sql_queries)
    expect(response.body).to include("AI summary")
    expect(response.body).to include("Launch brief summary")
    expect(response.body).to include("Sources")
  end

  it "references child tabs using their parent context in search results" do
    user = User.create!(email: "search-tabs@example.com", password: "password123")
    workspace = Workspace.create!(name: "Search Tabs", slug: "search-tabs")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    parent_page = Page.create!(workspace: workspace, created_by: user, title: "Strategy")
    child_tab_page = Page.create!(workspace: workspace, created_by: user, parent_page: parent_page, title: "Orbit notes")
    Block.create!(
      workspace: workspace,
      page: child_tab_page,
      created_by: user,
      block_type: "paragraph",
      content_json: {
        type: "doc",
        content: [ { type: "paragraph", content: [ { type: "text", text: "orbit tab detail" } ] } ]
      }
    )

    grid_parent = Page.create!(workspace: workspace, created_by: user, title: "Operations")
    grid_tab_page = Page.create!(workspace: workspace, created_by: user, parent_page: grid_parent, title: "Runbook")
    database = Database.create!(workspace: workspace, name: "Runbook grid", linked_page: grid_tab_page)
    DbRow.create!(workspace: workspace, database: database, title: "Orbit checklist", data_json: { notes: "orbit row context" })

    sign_in user
    get workspace_search_path(workspace_slug: workspace.slug), params: { q: "orbit" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Strategy / Orbit notes")
    expect(response.body).to include("Tab block")
    expect(response.body).to include("Grid tab row")
    expect(response.body).to include("Orbit checklist · Operations / Runbook")
  end

  it "routes top-level grid shell results to the grid instead of a standalone page" do
    user = User.create!(email: "search-grid-shell@example.com", password: "password123")
    workspace = Workspace.create!(name: "Search grid shells", slug: "search-grid-shells")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    shell_page = Page.create!(workspace: workspace, created_by: user, title: "Ops planning")
    database = Database.create!(workspace: workspace, created_by: user, name: "Ops grid", linked_page: shell_page)

    sign_in user
    get workspace_search_path(workspace_slug: workspace.slug), params: { q: "planning" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Grid")
    expect(response.body).to include("Ops planning")
    expect(response.body).to include(database_path(workspace_slug: workspace.slug, id: database.id))
    expect(response.body).not_to include(page_path(workspace_slug: workspace.slug, id: shell_page.id))
  end

  it "shows a clear notice when AI summary is rate-limited" do
    user = User.create!(email: "search-ai-rate-limited@example.com", password: "password123", openai_api_key: "sk-test")
    workspace = Workspace.create!(name: "AI Search Rate Limited", slug: "ai-search-rate-limited")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    Page.create!(workspace: workspace, created_by: user, title: "Launch Brief")

    allow(Search::AiRateLimiter).to receive(:allowed?)
      .with(user: user, workspace: workspace, operation: "semantic_search")
      .and_return(false)
    allow(Search::AiRateLimiter).to receive(:allowed?)
      .with(user: user, workspace: workspace, operation: "answer_generation")
      .and_return(false)

    sign_in user
    get workspace_search_path(workspace_slug: workspace.slug), params: { q: "launch" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("AI summary is temporarily rate-limited")
  end
end
