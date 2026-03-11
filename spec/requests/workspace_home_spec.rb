require "rails_helper"

RSpec.describe "Workspace home", type: :request do
  it "shows only the 3 most recently updated pages and databases" do
    user = User.create!(email: "home-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Home test", slug: "home-test")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    old_page = Page.create!(workspace: workspace, created_by: user, title: "Page 1 old")
    mid_page = Page.create!(workspace: workspace, created_by: user, title: "Page 2 mid")
    newer_page = Page.create!(workspace: workspace, created_by: user, title: "Page 3 newer")
    latest_page = Page.create!(workspace: workspace, created_by: user, title: "Page 4 latest")

    old_page.touch(time: 4.days.ago)
    mid_page.touch(time: 3.days.ago)
    newer_page.touch(time: 2.days.ago)
    latest_page.touch(time: 1.day.ago)

    old_db = Database.create!(workspace: workspace, name: "DB 1 old")
    mid_db = Database.create!(workspace: workspace, name: "DB 2 mid")
    newer_db = Database.create!(workspace: workspace, name: "DB 3 newer")
    latest_db = Database.create!(workspace: workspace, name: "DB 4 latest")

    old_db.touch(time: 4.days.ago)
    mid_db.touch(time: 3.days.ago)
    newer_db.touch(time: 2.days.ago)
    latest_db.touch(time: 1.day.ago)

    sign_in user
    get workspace_path(workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("notae-ai-usage-card")
    expect(response.body).to include("Today usage")
    expect(response.body).to include("notae-ai-usage-toggle")
    expect(response.body).to include("aria-expanded=\"false\"")
    expect(response.body).to include("notae-ai-rail-toggle")
    expect(response.body).to include("notae-ai-rail-reopen")
    expect(response.body).to include("notae-ai-floating-toggle")
    expect(response.body).to include("notae-ai-rail-overlay")
    expect(response.body).to include("notae-ai-loader")
    expect(response.body).to include("notae-ai-compose-swirl")
    expect(response.body).to include("notae-ai-prompt-input")
    expect(response.body).to include("Kalendārium")
    expect(response.body).to include("toggleFloatingRail")
    expect(response.body).to include("AI Conversation History")
    expect(response.body).to include("submitOnShortcut")
    expect(response.body).to include("notae-sidebar-collapse-toggle")
    expect(response.body).to include("notae-sidebar-dock")
    expect(response.body).to include("toggleSidebarCollapse")
    expect(response.body).not_to include("Current context:")
    expect(response.body).not_to include("Ask a question to start a conversation.")
    html = Nokogiri::HTML(response.body)

    page_titles = html.css(".notae-workspace-page-grid .notae-workspace-page-card-text strong").map(&:text)
    expect(page_titles).to eq([ "Page 4 latest", "Page 3 newer", "Page 2 mid" ])

    database_titles = html.css(".notae-auth-card .notae-workspace-home-link-grid .notae-home-workspace-item strong").map(&:text)
    normalized_database_titles = database_titles.map { |title| title.gsub(/\A\S+\s+/, "") }
    expect(normalized_database_titles).to include("DB 4 latest", "DB 3 newer", "DB 2 mid")
    expect(normalized_database_titles).not_to include("DB 1 old")
    expect(normalized_database_titles.count).to eq(3)

    hero_subtle_lines = html.css(".notae-workspace-home-hero .notae-page-subtle").map { |node| node.text.strip }
    expect(hero_subtle_lines).to eq([ "Workspace home" ])
  end

  it "renders the workspace library page for members" do
    user = User.create!(email: "library-member@example.com", password: "password123")
    workspace = Workspace.create!(name: "Library test", slug: "library-test")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    sign_in user
    get workspace_library_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Library")
  end

  it "renders the daily brief on the home page and the proactive overlay in shell layout" do
    user = User.create!(email: "home-knowledge-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Knowledge home", slug: "knowledge-home")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    Database.create!(workspace: workspace, name: "Tasks")

    KnowledgeSuggestion.create!(
      workspace: workspace,
      user: user,
      kind: KnowledgeSuggestion::KIND_DAILY_SUMMARY,
      status: KnowledgeSuggestion::STATUS_ACTIVE,
      title: "Daily workspace brief",
      summary: "Review the critical blockers before noon. [1]",
      insights_json: [ "Approvals remain outstanding. [1]" ],
      task_suggestions_json: [
        { "title" => "Follow up with approver", "owner" => "Errol", "rationale" => "Approval is still missing. [1]" }
      ],
      sources_json: [ { "index" => 1, "title" => "Launch note", "url" => "/w/#{workspace.slug}/pages/test" } ],
      generated_for_date: Date.current,
      generated_at: Time.current
    )
    KnowledgeSuggestion.create!(
      workspace: workspace,
      user: user,
      kind: KnowledgeSuggestion::KIND_PROACTIVE,
      status: KnowledgeSuggestion::STATUS_ACTIVE,
      title: "Suggested next step",
      summary: "Escalate the approval gap this afternoon. [1]",
      task_suggestions_json: [
        { "title" => "Escalate approval gap", "owner" => "Errol", "rationale" => "This is blocking progress. [1]" }
      ],
      sources_json: [ { "index" => 1, "title" => "Launch note", "url" => "/w/#{workspace.slug}/pages/test" } ],
      generated_at: Time.current,
      expires_at: 6.hours.from_now
    )

    sign_in user
    get workspace_path(workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Daily workspace brief")
    expect(response.body).to include("Review the critical blockers before noon. [1]")
    expect(response.body).to include("notae-knowledge-overlay")
    expect(response.body).to include("Escalate the approval gap this afternoon. [1]")
    expect(response.body).to include("Choose tasks grid")
    expect(response.body).to include("Create Nota")
    expect(response.body).to include("Dismiss")
  end
end
