require "rails_helper"

RSpec.describe "Workspace home", type: :request do
  include ActiveSupport::Testing::TimeHelpers

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

  it "renders the daily brief on the home page and routes proactive suggestions through the ai rail and home page card" do
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
    expect(response.body).to include("AI suggestion")
    expect(response.body).to include("knowledge-suggestion-")
    expect(response.body).to include("Update available from Agent")
    expect(response.body).to include("Open full window")
    expect(response.body).to include("Escalate the approval gap this afternoon. [1]")
    expect(response.body).to include("Choose tasks grid")
    expect(response.body).to include("Create Nota")
    expect(response.body).to include("Create Grid")
    expect(response.body).to include("Dismiss")
    expect(response.body).not_to include("notae-knowledge-overlay")
  end

  it "throttles proactive suggestion generation across quick page switches" do
    user = User.create!(email: "home-knowledge-throttle@example.com", password: "password123", openai_api_key: "sk-test")
    workspace = Workspace.create!(name: "Knowledge throttle", slug: "knowledge-throttle")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    allow(Search::PersistKnowledgeSuggestionService).to receive(:ensure_proactive!).and_return(nil)

    sign_in user

    travel_to(Time.utc(2026, 3, 21, 10, 0, 0)) do
      get workspace_path(workspace.slug)
      expect(response).to have_http_status(:ok)

      get workspace_library_path(workspace_slug: workspace.slug)
      expect(response).to have_http_status(:ok)
    end

    expect(Search::PersistKnowledgeSuggestionService).to have_received(:ensure_proactive!).once.with(user: user, workspace: workspace)
  end

  it "renders pending agent draft actions on the workspace home page" do
    user = User.create!(email: "home-agent-action-owner@example.com", password: "password123")
    author = User.create!(email: "home-agent-action-author@example.com", password: "password123")
    workspace = Workspace.create!(name: "Agent action home", slug: "agent-action-home")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    Membership.create!(workspace: workspace, user: author, role: :member)

    AgentActions::DraftCreator.new(
      workspace: workspace,
      actor: author,
      attributes: {
        title: "Draft standup summary email",
        proposed_by: "manual",
        target_system: "gmail",
        draft_type: "email_draft",
        payload_json: {
          "to" => [ "team@example.com" ],
          "subject" => "Standup summary",
          "body" => "Dry-run summary."
        }
      }
    ).call

    sign_in user
    get workspace_path(workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Agent draft actions")
    expect(response.body).to include("Draft standup summary email")
    expect(response.body).to include("Review drafts")
    expect(response.body).to include("New draft")
  end

  it "renders AI agent updates in the rail and exposes the polling endpoint" do
    user = User.create!(email: "home-ai-agent-updates@example.com", password: "password123")
    workspace = Workspace.create!(name: "Home AI Agent Updates", slug: "home-ai-agent-updates")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    agent_action = AgentAction.create!(
      workspace: workspace,
      user: user,
      proposed_by: "ai_assistant",
      target_system: "gmail",
      draft_type: "email_draft",
      title: "Quarterly review email",
      payload_json: {
        "to" => [ "team@example.com" ],
        "cc" => [],
        "subject" => "Quarterly review",
        "body" => "Please review the quarterly update."
      },
      status: AgentAction::STATUS_PENDING,
      approval_required: true,
      dry_run: true
    )
    agent_action.update_column(:updated_at, 10.minutes.ago)

    workflow_run = WorkflowRun.create!(
      workspace: workspace,
      user: user,
      workflow_kind: WorkflowRun::KIND_CREATE_TASK,
      status: WorkflowRun::STATUS_SUCCEEDED,
      trigger_source: "automation_agent",
      queued_at: 7.minutes.ago,
      finished_at: 6.minutes.ago,
      confidence_score: 1.0,
      result_json: { "title" => "Roadmap follow-up" }
    )
    workflow_run.update_column(:updated_at, 5.minutes.ago)

    sign_in user
    get workspace_path(workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("notae-ai-agent-toast")
    expect(response.body).to include("data-ai-rail-agent-updates-path-value=\"#{workspace_ai_assistant_updates_path(workspace_slug: workspace.slug)}\"")
    expect(response.body).to include("Update available from Agent")
    expect(response.body).to include("Open full window")
    expect(response.body).to include("Quarterly review email")
    expect(response.body).to include("Roadmap follow-up")

    document = Nokogiri::HTML.parse(response.body)
    update_cards = document.css(".notae-ai-message.is-agent-update")
    update_titles = update_cards.css(".notae-ai-message-body").map(&:text)

    expect(update_cards.count).to eq(2)
    expect(update_titles).to include("Quarterly review email", "Roadmap follow-up")
  end
end
