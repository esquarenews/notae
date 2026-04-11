require "rails_helper"

RSpec.describe "Workspace home", type: :request do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  def create_indexed_page(workspace:, user:, title:, text:)
    page = Page.create!(workspace: workspace, created_by: user, title: title)
    SearchChunk.create!(
      workspace: workspace,
      source_type: SearchChunk::SOURCE_PAGE,
      source_id: page.id,
      page: page,
      chunk_index: 0,
      text: text,
      token_count: text.split.size,
      content_hash: "workspace-home-chunk-#{page.id}",
      source_content_hash: "workspace-home-source-#{page.id}",
      source_uri: "/w/#{workspace.slug}/pages/#{page.id}",
      source_title: page.title,
      metadata_json: {}
    )
    page
  end

  around do |example|
    clear_enqueued_jobs
    clear_performed_jobs
    Rails.cache.clear
    example.run
    clear_enqueued_jobs
    clear_performed_jobs
    Rails.cache.clear
  end

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
    expect(response.headers["X-Notae-Perf-Action"]).to eq("WorkspaceHomeController#show")
    expect(response.headers["X-Notae-Perf-Sql-Queries"]).to be_present
    expect(response.body).to include("Open AI assistant")
    expect(response.body).to include("notae-ai-rail-reopen")
    expect(response.body).to include("notae-ai-floating-toggle")
    expect(response.body).to include("notae-ai-loader")
    expect(response.body).to include("Kalendārium")
    expect(response.body).to include("AI Conversation History")
    expect(response.body).to include("notae-sidebar-collapse-toggle")
    expect(response.body).to include("notae-sidebar-dock")
    expect(response.body).to include("toggleSidebarCollapse")
    expect(response.body).not_to include("Current context:")
    expect(response.body).not_to include("Ask a question to start a conversation.")
    html = Nokogiri::HTML(response.body)

    ai_rail_frame = html.at_css("turbo-frame#ai_rail_panel")
    expect(ai_rail_frame).to be_present
    expect(ai_rail_frame["data-controller"]).to include("ai-rail-loader")
    expect(ai_rail_frame["data-ai-rail-loader-src-value"]).to eq(workspace_ai_assistant_panel_path(workspace_slug: workspace.slug))

    page_titles = html.css(".notae-workspace-page-grid .notae-workspace-page-card-text strong").map(&:text)
    expect(page_titles).to eq([ "Page 4 latest", "Page 3 newer", "Page 2 mid" ])

    database_titles = html.css(".notae-auth-card .notae-workspace-home-link-grid .notae-home-workspace-item strong").map { |node| node.text.squish }
    normalized_database_titles = database_titles.map { |title| title.sub(/\A\S+\s+/, "") }
    expect(normalized_database_titles).to include("DB 4 latest", "DB 3 newer", "DB 2 mid")
    expect(normalized_database_titles).not_to include("DB 1 old")
    expect(normalized_database_titles.count).to eq(3)

    hero_subtle_lines = html.css(".notae-workspace-home-hero .notae-page-subtle").map { |node| node.text.strip }
    expect(hero_subtle_lines).to eq([ "Workspace home" ])
  end

  it "renders the workspace colour marker and top border for the active workspace" do
    user = User.create!(email: "home-colour-owner@example.com", password: "password123")
    workspace = Workspace.create!(
      name: "Colour home",
      slug: "colour-home",
      workspace_color: Workspace::WORKSPACE_COLOR_OPTIONS.fourth.fetch(:value)
    )
    Membership.create!(workspace: workspace, user: user, role: :owner)

    sign_in user
    get workspace_path(workspace.slug)

    expect(response).to have_http_status(:ok)

    document = Nokogiri::HTML(response.body)
    shell = document.at_css(".notae-shell")
    marker = document.at_css(".notae-workspace-chip .notae-workspace-color-dot")
    get workspace_sidebar_sections_path(workspace_slug: workspace.slug)
    expect(response).to have_http_status(:ok)
    sidebar_document = Nokogiri::HTML(response.body)
    workspace_link = sidebar_document.css(".notae-sidebar-section .notae-sidebar-page-title").find { |node| node.text.include?("Colour home") }

    expect(shell&.[]("style")).to include("--notae-workspace-color: #{workspace.workspace_color}")
    expect(marker&.[]("style")).to include("--notae-workspace-color-swatch: #{workspace.workspace_color}")
    expect(workspace_link.to_html).to include("--notae-workspace-color-swatch: #{workspace.workspace_color}")
  end

  it "renders the bottom-right notification bar with recent-only mail and update alerts plus dismiss controls" do
    travel_to Time.zone.parse("2026-04-11 10:00:00") do
      user = User.create!(email: "home-status-bar-owner@example.com", password: "password123", time_zone: "Australia/Melbourne")
      workspace = Workspace.create!(name: "Status home", slug: "status-home", shell_status_bar_mode: "all")
      Membership.create!(workspace: workspace, user: user, role: :owner)

      calendar = KalendariumCalendar.create!(
        workspace: workspace,
        created_by: user,
        name: "Primary",
        color_hex: "#2563eb",
        time_zone: "Australia/Melbourne",
        source_kind: "local"
      )
      KalendariumEvent.create!(
        workspace: workspace,
        kalendarium_calendar: calendar,
        created_by: user,
        updated_by: user,
        title: "Client review",
        starts_at_utc: 10.minutes.from_now,
        ends_at_utc: 40.minutes.from_now
      )

      account = EpistulariumAccount.create!(
        workspace: workspace,
        owner: user,
        created_by: user,
        provider: "gmail",
        label: "Inbox",
        access_token: "token"
      )
      EpistulariumMessage.create!(
        workspace: workspace,
        epistularium_account: account,
        provider_message_id: "status-msg-1",
        mailbox: "inbox",
        unread: true,
        subject: "Unread message",
        received_at: 1.minute.ago
      )
      EpistulariumMessage.create!(
        workspace: workspace,
        epistularium_account: account,
        provider_message_id: "status-msg-old",
        mailbox: "inbox",
        unread: true,
        subject: "Old unread message",
        received_at: 2.days.ago
      )

      Notification.create!(
        workspace: workspace,
        recipient: user,
        actor: user,
        notification_type: Notification::TYPE_MENTION,
        metadata: {}
      )
      Notification.create!(
        workspace: workspace,
        recipient: user,
        actor: user,
        notification_type: Notification::TYPE_MENTION,
        metadata: {},
        created_at: 2.days.ago,
        updated_at: 2.days.ago
      )

      sign_in user
      get workspace_path(workspace.slug)

      expect(response).to have_http_status(:ok)

      document = Nokogiri::HTML(response.body)
      bar = document.at_css(".notae-shell-status-bar")
      links = document.css(".notae-shell-status-bar-link").map { |node| [ node.text.squish, node["href"] ] }
      controls = document.css(".notae-shell-status-bar-control")

      expect(bar).to be_present
      expect(bar["data-controller"]).to include("notification-bar")
      expect(bar["data-notification-bar-time-zone-value"]).to eq("Australia/Melbourne")
      expect(bar["data-notification-bar-workspace-key-value"]).to eq(workspace.slug)
      expect(document.text).to include("Client review")
      expect(document.text).to include("Starts in 10 min")
      expect(document.text).to include("1 email just came in")
      expect(document.text).to include("1 new workspace update")
      expect(document.text).not_to include("Unread inbox messages")
      expect(controls.count).to eq(6)
      expect(links).to include([ a_string_including("Client review"), kalendarium_path(workspace_slug: workspace.slug) ])
      expect(links).to include([ a_string_including("1 email just came in"), workspace_epistularium_path(workspace_slug: workspace.slug) ])
      expect(links).to include([ a_string_including("1 new workspace update"), workspace_notifications_path(workspace_slug: workspace.slug) ])
    end
  end

  it "styles the notification bar and alert cards with the same exaggerated glass treatment" do
    stylesheet = Rails.root.join("app/assets/stylesheets/application.css").read

    expect(stylesheet).to include(".notae-shell-status-bar {\n  position: fixed;")
    expect(stylesheet).to include("  background-color: color-mix(in srgb, var(--notae-panel-bg) 4%, transparent);")
    expect(stylesheet).to include("  background:\n    linear-gradient(\n      180deg,\n      color-mix(in srgb, var(--notae-panel-elevated) 10%, transparent),\n      color-mix(in srgb, var(--notae-panel-bg) 4%, transparent)\n    );")
    expect(stylesheet).to include("  -webkit-backdrop-filter: blur(40px) saturate(1.08);")
    expect(stylesheet).to include(".notae-shell-status-bar-item {\n  display: grid;")
    expect(stylesheet).to include("  background-color: color-mix(in srgb, var(--notae-panel-bg) 4%, transparent);")
    expect(stylesheet).to include(".notae-shell-status-bar-control {\n  width: 1.8rem;")
  end

  it "does not surface child tabs as standalone Notarum or Grids on the home page" do
    user = User.create!(email: "home-tab-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Home tabs", slug: "home-tabs")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    parent_page = Page.create!(workspace: workspace, created_by: user, title: "Launch plan")
    child_tab = Page.create!(workspace: workspace, created_by: user, parent_page: parent_page, title: "Budget tab")
    top_level_page = Page.create!(workspace: workspace, created_by: user, title: "Standalone nota")
    top_level_page.touch(time: 1.hour.ago)
    child_tab.touch(time: Time.current)

    grid_parent = Page.create!(workspace: workspace, created_by: user, title: "Operations")
    grid_tab_page = Page.create!(workspace: workspace, created_by: user, parent_page: grid_parent, title: "Runbook tab")
    tab_database = Database.create!(workspace: workspace, name: "Runbook grid", linked_page: grid_tab_page)
    top_level_database = Database.create!(workspace: workspace, name: "Standalone grid")
    tab_database.touch(time: Time.current)
    top_level_database.touch(time: 1.hour.ago)

    sign_in user
    get workspace_path(workspace.slug)

    expect(response).to have_http_status(:ok)

    html = Nokogiri::HTML(response.body)
    page_titles = html.css(".notae-workspace-page-grid .notae-workspace-page-card-text strong").map(&:text)
    expect(page_titles).to include("Standalone nota")
    expect(page_titles).not_to include("Budget tab")

    database_titles = html.css(".notae-auth-card .notae-workspace-home-link-grid .notae-home-workspace-item strong").map { |node| node.text.squish }
    normalized_database_titles = database_titles.map { |title| title.sub(/\A\S+\s+/, "") }
    expect(normalized_database_titles).to include("Standalone grid")
    expect(normalized_database_titles).not_to include("Runbook grid")

    get workspace_sidebar_sections_path(workspace_slug: workspace.slug)
    expect(response).to have_http_status(:ok)
    sidebar_labels = Nokogiri::HTML(response.body).css(".notae-sidebar-section .notae-sidebar-page-title").map { |node| node.text.squish }
    expect(sidebar_labels).to include(match(/Standalone nota/))
    expect(sidebar_labels).to include(match(/Standalone grid/))
    expect(sidebar_labels).not_to include(match(/Budget tab/))
    expect(sidebar_labels).not_to include(match(/Runbook grid/))
  end

  it "does not surface top-level grid shell pages as standalone Notarum on the home page" do
    user = User.create!(email: "home-grid-shell-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Home grid shells", slug: "home-grid-shells")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    standalone_page = Page.create!(workspace: workspace, created_by: user, title: "Standalone nota")
    grid_shell = Page.create!(workspace: workspace, created_by: user, title: "Grid shell page")
    database = Database.create!(workspace: workspace, created_by: user, name: "Ops grid", linked_page: grid_shell)
    standalone_page.touch(time: Time.current)
    database.touch(time: 1.hour.ago)

    sign_in user
    get workspace_path(workspace.slug)

    expect(response).to have_http_status(:ok)

    html = Nokogiri::HTML(response.body)
    page_titles = html.css(".notae-workspace-page-grid .notae-workspace-page-card-text strong").map(&:text)
    database_titles = html.css(".notae-auth-card .notae-workspace-home-link-grid .notae-home-workspace-item strong").map { |node| node.text.squish }
    normalized_database_titles = database_titles.map { |title| title.sub(/\A\S+\s+/, "") }

    expect(page_titles).to include("Standalone nota")
    expect(page_titles).not_to include("Grid shell page")
    expect(normalized_database_titles).to include("Ops grid")

    get workspace_sidebar_sections_path(workspace_slug: workspace.slug)
    expect(response).to have_http_status(:ok)
    sidebar_labels = Nokogiri::HTML(response.body).css(".notae-sidebar-section .notae-sidebar-page-title").map { |node| node.text.squish }
    expect(sidebar_labels).to include(match(/Standalone nota/))
    expect(sidebar_labels).to include(match(/Ops grid/))
    expect(sidebar_labels).not_to include(match(/Grid shell page/))
  end

  it "lazy loads recent page cover images on the workspace home page" do
    user = User.create!(email: "home-cover-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Home cover", slug: "home-cover")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    page = Page.create!(workspace: workspace, created_by: user, title: "Covered page")

    Tempfile.create([ "workspace-home-cover", ".png" ]) do |file|
      file.write("fake-png-data")
      file.rewind
      page.cover_image.attach(io: file, filename: "cover.png", content_type: "image/png")
    end

    sign_in user
    get workspace_path(workspace.slug)

    expect(response).to have_http_status(:ok)

    document = Nokogiri::HTML(response.body)
    cover_image = document.at_css(".notae-workspace-page-card-cover-image")
    expect(cover_image).to be_present
    expect(cover_image["loading"]).to eq("lazy")
    expect(cover_image["decoding"]).to eq("async")
  end

  it "renders remote Unsplash covers on the workspace home page" do
    user = User.create!(email: "home-remote-cover-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Home remote cover", slug: "home-remote-cover")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    Page.create!(
      workspace: workspace,
      created_by: user,
      title: "Unsplash page card",
      cover_remote_url: "https://images.unsplash.com/home-cover-regular",
      cover_remote_thumb_url: "https://images.unsplash.com/home-cover-small",
      cover_artist_name: "Mika Frame",
      cover_artist_url: "https://unsplash.com/@mika?utm_source=notae&utm_medium=referral",
      cover_source_name: "Unsplash",
      cover_source_url: "https://unsplash.com/?utm_source=notae&utm_medium=referral"
    )

    sign_in user
    get workspace_path(workspace.slug)

    expect(response).to have_http_status(:ok)

    document = Nokogiri::HTML(response.body)
    cover_image = document.at_css(".notae-workspace-page-card-cover-image")
    expect(cover_image).to be_present
    expect(cover_image["src"]).to include("images.unsplash.com/home-cover-small")
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
    expect(response.body).to include("Next brief")
    expect(response.body).to include("Review the critical blockers before noon. [1]")
    expect(response.body).to include("Important updates")
    expect(response.body).to include("AI suggestion")
    expect(response.body).to include("Agent draft actions")
    expect(response.body).to include("knowledge-suggestion-")
    expect(response.body).to include("Escalate the approval gap this afternoon. [1]")
    expect(response.body).to include("Choose tasks grid")
    expect(response.body).to include("Create Nota")
    expect(response.body).to include("Open Kalendārium")
    expect(response.body).to include("Dismiss")
    expect(response.body).not_to include("notae-knowledge-overlay")

    get workspace_ai_assistant_panel_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Update available from Agent")
    expect(response.body).to include("Open full window")
  end

  it "queues a daily brief in the background and shows pending state instead of blocking the page load" do
    user = User.create!(email: "home-knowledge-daily-pending@example.com", password: "password123", openai_api_key: "sk-test")
    workspace = Workspace.create!(name: "Knowledge daily pending", slug: "knowledge-daily-pending")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    create_indexed_page(
      workspace: workspace,
      user: user,
      title: "Daily context",
      text: "The workspace contains actionable indexed context for a daily brief."
    )

    sign_in user

    travel_to(Time.utc(2026, 3, 21, 7, 30, 0)) do
      expect do
        get workspace_path(workspace.slug)
      end.to have_enqueued_job(Search::GenerateKnowledgeSuggestionJob)
        .with(user.id, workspace.id, KnowledgeSuggestion::KIND_DAILY_SUMMARY)
        .on_queue("default")
    end

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Preparing daily workspace brief")
    expect(response.body).to include("The page is ready.")
    expect(response.body).to include("Next brief")
  end

  it "shows the latest available brief while a new daily brief is pending" do
    user = User.create!(email: "home-knowledge-latest-brief@example.com", password: "password123", openai_api_key: "sk-test")
    workspace = Workspace.create!(name: "Knowledge latest brief", slug: "knowledge-latest-brief")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    Database.create!(workspace: workspace, name: "Tasks")
    create_indexed_page(
      workspace: workspace,
      user: user,
      title: "Fresh context",
      text: "Fresh indexed context exists so a new daily brief can be queued."
    )
    KnowledgeSuggestion.create!(
      workspace: workspace,
      user: user,
      kind: KnowledgeSuggestion::KIND_DAILY_SUMMARY,
      status: KnowledgeSuggestion::STATUS_ACTIVE,
      title: "Yesterday workspace brief",
      summary: "Yesterday still has the most useful summary available. [1]",
      insights_json: [ "Carry forward the unfinished approvals. [1]" ],
      sources_json: [ { "index" => 1, "title" => "Yesterday note", "url" => "/w/#{workspace.slug}/pages/yesterday" } ],
      generated_for_date: Date.current - 1.day,
      generated_at: 1.day.ago
    )

    sign_in user

    travel_to(Time.utc(2026, 3, 21, 7, 30, 0)) do
      expect do
        get workspace_path(workspace.slug)
      end.to have_enqueued_job(Search::GenerateKnowledgeSuggestionJob)
        .with(user.id, workspace.id, KnowledgeSuggestion::KIND_DAILY_SUMMARY)
        .on_queue("default")
    end

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Latest available brief")
    expect(response.body).to include("Yesterday workspace brief")
    expect(response.body).to include("Yesterday still has the most useful summary available. [1]")
    expect(response.body).to include("Preparing daily workspace brief")
    expect(response.body).to include("Next brief")
  end

  it "renders an empty workspace home when AI suggestion enqueue fails" do
    user = User.create!(email: "home-knowledge-enqueue-failure@example.com", password: "password123", openai_api_key: "sk-test")
    workspace = Workspace.create!(name: "Empty workspace", slug: "empty-workspace")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    create_indexed_page(
      workspace: workspace,
      user: user,
      title: "Failure context",
      text: "This workspace has indexed context so the enqueue path is exercised."
    )

    sign_in user
    allow(Search::GenerateKnowledgeSuggestionJob).to receive(:perform_later).and_raise(ActiveJob::EnqueueError, "queue offline")

    travel_to(Time.utc(2026, 3, 21, 7, 30, 0)) do
      get workspace_path(workspace.slug)
    end

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Failure context")
    expect(response.body).to include("No grids yet.")
    expect(response.body).not_to include("Preparing daily workspace brief")

    failure_log = AiUsageLog.order(:created_at).last
    expect(failure_log).to be_present
    expect(failure_log.user).to eq(user)
    expect(failure_log.workspace).to eq(workspace)
    expect(failure_log.operation).to eq(AiUsageLog::OP_KNOWLEDGE_SUGGESTION_FAILURE)
    expect(failure_log.model).to eq("background_job")
    expect(failure_log.metadata).to include(
      "kind" => KnowledgeSuggestion::KIND_DAILY_SUMMARY,
      "stage" => "enqueue",
      "error_class" => "ActiveJob::EnqueueError"
    )
  end

  it "throttles proactive suggestion generation across quick page switches by queueing background work once" do
    user = User.create!(email: "home-knowledge-throttle@example.com", password: "password123", openai_api_key: "sk-test")
    workspace = Workspace.create!(name: "Knowledge throttle", slug: "knowledge-throttle")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    create_indexed_page(
      workspace: workspace,
      user: user,
      title: "Proactive context",
      text: "Fresh indexed context exists so proactive generation can be queued."
    )

    sign_in user

    travel_to(Time.utc(2026, 3, 21, 10, 0, 0)) do
      expect do
        get workspace_path(workspace.slug)
      end.to have_enqueued_job(Search::GenerateKnowledgeSuggestionJob)
        .with(user.id, workspace.id, KnowledgeSuggestion::KIND_PROACTIVE)
        .on_queue("default")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Preparing AI suggestion")

      get workspace_library_path(workspace_slug: workspace.slug)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(data-ai-rail-loader-src-value="#{workspace_ai_assistant_panel_path(workspace_slug: workspace.slug)}"))

      get workspace_ai_assistant_panel_path(workspace_slug: workspace.slug)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Preparing AI suggestion")
    end

    proactive_jobs = enqueued_jobs.select do |job|
      job[:job] == Search::GenerateKnowledgeSuggestionJob &&
        Array(job[:args]).last == KnowledgeSuggestion::KIND_PROACTIVE
    end
    expect(proactive_jobs.size).to eq(1)
  end

  it "skips knowledge suggestion generation for workspaces without indexed context" do
    user = User.create!(email: "home-knowledge-empty-context@example.com", password: "password123", openai_api_key: "sk-test")
    workspace = Workspace.create!(name: "No indexed context", slug: "no-indexed-context")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    sign_in user

    travel_to(Time.utc(2026, 3, 21, 10, 0, 0)) do
      expect do
        get workspace_path(workspace.slug)
      end.not_to have_enqueued_job(Search::GenerateKnowledgeSuggestionJob)
    end

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Preparing daily workspace brief")
    expect(response.body).not_to include("Preparing AI suggestion")

    clear_enqueued_jobs

    travel_to(Time.utc(2026, 3, 21, 10, 0, 0)) do
      expect do
        get workspace_ai_assistant_panel_path(workspace_slug: workspace.slug)
      end.not_to have_enqueued_job(Search::GenerateKnowledgeSuggestionJob)
    end

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Preparing AI suggestion")
  end

  it "does not overflow the session cookie when switching across many workspaces" do
    user = User.create!(email: "home-session-overflow@example.com", password: "password123", openai_api_key: "sk-test")
    visited_workspaces = Array.new(40) do |index|
      workspace = Workspace.create!(name: "Session workspace #{index}", slug: "session-workspace-#{index}")
      Membership.create!(workspace: workspace, user: user, role: :owner)
      page = create_indexed_page(
        workspace: workspace,
        user: user,
        title: "Visited page #{index}",
        text: "Indexed context #{index} keeps suggestion generation eligible while switching workspaces."
      )
      [ workspace, page ]
    end

    sign_in user

    travel_to(Time.utc(2026, 3, 21, 10, 0, 0)) do
      expect do
        visited_workspaces.each do |workspace, page|
          get page_path(workspace_slug: workspace.slug, id: page.id)
          expect(response).to have_http_status(:ok)
          expect(response.headers["Set-Cookie"].to_s.bytesize).to be < 3900

          get workspace_path(workspace.slug)
          expect(response).to have_http_status(:ok)
          expect(response.headers["Set-Cookie"].to_s.bytesize).to be < 3900
        end

        Rails.cache.clear
        get workspace_path(visited_workspaces.last.first.slug)
        expect(response).to have_http_status(:ok)
        expect(response.headers["Set-Cookie"].to_s.bytesize).to be < 3900
      end.not_to raise_error
    end
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
    expect(response.body).to include("Important updates")
    expect(response.body).to include("Agent draft actions")
    expect(response.body).to include("Draft standup summary email")
    expect(response.body).to include("Review drafts")
    expect(response.body).to include("New draft")
  end

  it "renders AI agent updates in the lazy-loaded rail panel and exposes the polling endpoint" do
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
    get workspace_ai_assistant_panel_path(workspace_slug: workspace.slug)

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

  it "renders AI rail entries in timeline order across conversations and agent updates in the lazy-loaded panel" do
    user = User.create!(email: "home-ai-rail-timeline@example.com", password: "password123")
    workspace = Workspace.create!(name: "Home AI Rail Timeline", slug: "home-ai-rail-timeline")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    older_conversation = AiConversation.create!(
      user: user,
      workspace: workspace,
      scope: Search::AssistantQueryService::SCOPE_WORKSPACE,
      status: AiConversation::STATUS_SUCCESS,
      prompt: "Older question",
      answer: "Older answer",
      sources: []
    )
    older_conversation.update_column(:created_at, 30.minutes.ago)

    agent_action = AgentAction.create!(
      workspace: workspace,
      user: user,
      proposed_by: "ai_assistant",
      target_system: "gmail",
      draft_type: "email_draft",
      title: "Middle update",
      payload_json: {
        "to" => [ "team@example.com" ],
        "cc" => [],
        "subject" => "Middle subject",
        "body" => "Middle body"
      },
      status: AgentAction::STATUS_PENDING,
      approval_required: true,
      dry_run: true
    )
    agent_action.update_column(:updated_at, 20.minutes.ago)

    newer_conversation = AiConversation.create!(
      user: user,
      workspace: workspace,
      scope: Search::AssistantQueryService::SCOPE_WORKSPACE,
      status: AiConversation::STATUS_SUCCESS,
      prompt: "Newer question",
      answer: "Newer answer",
      sources: []
    )
    newer_conversation.update_column(:created_at, 10.minutes.ago)

    sign_in user
    get workspace_ai_assistant_panel_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)

    document = Nokogiri::HTML.parse(response.body)
    timeline_entries = document.css(".notae-ai-thread .notae-ai-thread-entry")

    expect(timeline_entries.count).to eq(3)
    expect(timeline_entries[0].text).to include("Older question")
    expect(timeline_entries[0].text).to include("Older answer")
    expect(timeline_entries[1].text).to include("Middle update")
    expect(timeline_entries[1].text).to include("Update available from Agent")
    expect(timeline_entries[2].text).to include("Newer question")
    expect(timeline_entries[2].text).to include("Newer answer")
  end
end
