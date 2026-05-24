require "rails_helper"

RSpec.describe "Notifications", type: :request do
  include ActiveJob::TestHelper

  around do |example|
    ActionMailer::Base.deliveries.clear
    clear_enqueued_jobs

    perform_enqueued_jobs do
      example.run
    end
  ensure
    ActionMailer::Base.deliveries.clear
    clear_enqueued_jobs
  end

  it "creates mention notifications and updates unread count when read" do
    author = User.create!(email: "mention-author@example.com", password: "password123")
    mentioned = User.create!(email: "mention-target@example.com", password: "password123", time_zone: "Australia/Melbourne")
    workspace = Workspace.create!(name: "Mentions", slug: "mentions")
    Membership.create!(workspace: workspace, user: author, role: :owner)
    Membership.create!(workspace: workspace, user: mentioned, role: :member)
    page = Page.create!(workspace: workspace, created_by: author, title: "Mentions Page")

    sign_in author
    post page_comments_path(workspace_slug: workspace.slug, page_id: page.id),
         params: { comment: { body: "Please review this @mention-target@example.com" } }
    notification = Notification.where(recipient: mentioned).last
    expect(notification).to be_present
    expect(notification.read_at).to be_nil
    expect(ActionMailer::Base.deliveries.size).to eq(1)
    mail = ActionMailer::Base.deliveries.last
    expect(mail.to).to eq([ mentioned.email ])
    expect(mail.from).to include("noreply@notae.local")
    expect(mail[:from].decoded).to include("Notae")
    expect(mail.subject).to include("mentioned you")
    expect(mail.body.encoded).to include("Please review this @mention-target@example.com")

    sign_out author
    sign_in mentioned
    get workspace_notifications_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.headers["X-Notae-Perf-Action"]).to eq("NotificationsController#index")
    expect(response.headers["X-Notae-Perf-Sql-Queries"]).to be_present
    expect(response.headers["X-Notae-Perf-Sql-Queries"].to_i).to be <= Notae::RequestPerformanceStore.budget_for(action: "NotificationsController#index").fetch(:sql_queries)
    expect(response.body).to include("notae-utility-page")
    expect(response.body).to include("notae-utility-notification-item")
    expect(response.body).to include("mentioned you")
    expect(response.body).to include("Unread: 1")
    expect(response.body).to include(notification.created_at.in_time_zone(mentioned.time_zone).strftime("%a %-d %b %Y · %-I:%M %p"))

    patch read_workspace_notification_path(workspace_slug: workspace.slug, id: notification.id)
    expect(notification.reload.read_at).to be_present

    get workspace_notifications_path(workspace_slug: workspace.slug)
    expect(response.body).to include("Unread: 0")
  end

  it "uses the system sender identity for mention emails when actor has legacy SMTP settings" do
    author = User.create!(
      email: "mention-smtp-author@example.com",
      password: "password123",
      smtp_address: "smtp.example.com",
      smtp_port: 587,
      smtp_domain: "example.com",
      smtp_username: "smtp-user",
      smtp_password: "smtp-password-123",
      smtp_authentication: "login",
      smtp_enable_starttls_auto: true,
      smtp_from_name: "Notae Alerts",
      smtp_from_email: "alerts@example.com"
    )
    mentioned = User.create!(email: "mention-smtp-target@example.com", password: "password123")
    workspace = Workspace.create!(name: "Mentions SMTP", slug: "mentions-smtp")
    Membership.create!(workspace: workspace, user: author, role: :owner)
    Membership.create!(workspace: workspace, user: mentioned, role: :member)
    page = Page.create!(workspace: workspace, created_by: author, title: "Mentions SMTP Page")
    sign_in author

    post page_comments_path(workspace_slug: workspace.slug, page_id: page.id),
         params: { comment: { body: "Please review this @mention-smtp-target@example.com" } }

    sent_mail = ActionMailer::Base.deliveries.last
    expect(sent_mail.to).to eq([ mentioned.email ])
    expect(sent_mail[:from].decoded).to include("Notae")
    expect(sent_mail.from).to include("noreply@notae.local")
  end

  it "does not send mention email when recipient disables activity email notifications" do
    author = User.create!(email: "mention-author-no-email@example.com", password: "password123")
    mentioned = User.create!(
      email: "mention-target-no-email@example.com",
      password: "password123",
      email_notify_activity: false
    )
    workspace = Workspace.create!(name: "Mentions no email", slug: "mentions-no-email")
    Membership.create!(workspace: workspace, user: author, role: :owner)
    Membership.create!(workspace: workspace, user: mentioned, role: :member)
    page = Page.create!(workspace: workspace, created_by: author, title: "Mentions Page no email")

    sign_in author

    expect do
      post page_comments_path(workspace_slug: workspace.slug, page_id: page.id),
           params: { comment: { body: "Please review this @mention-target-no-email@example.com" } }
    end.not_to change { ActionMailer::Base.deliveries.size }

    notification = Notification.where(recipient: mentioned).last
    expect(notification).to be_present
  end

  it "does not allow viewing another user's notifications" do
    actor = User.create!(email: "notif-actor-2@example.com", password: "password123")
    recipient = User.create!(email: "notif-recipient-2@example.com", password: "password123")
    outsider = User.create!(email: "notif-outsider@example.com", password: "password123")
    workspace = Workspace.create!(name: "Notif Access", slug: "notif-access")
    Membership.create!(workspace: workspace, user: recipient, role: :member)
    Membership.create!(workspace: workspace, user: outsider, role: :member)
    notification = Notification.create!(workspace: workspace, actor: actor, recipient: recipient, notification_type: "mention", metadata: {})

    sign_in outsider
    patch read_workspace_notification_path(workspace_slug: workspace.slug, id: notification.id)

    expect(response).to have_http_status(:not_found)
    expect(notification.reload.read_at).to be_nil
  end

  it "renders agent action approval notifications in the inbox" do
    author = User.create!(email: "notif-agent-author@example.com", password: "password123")
    approver = User.create!(email: "notif-agent-approver@example.com", password: "password123")
    workspace = Workspace.create!(name: "Notif Agent", slug: "notif-agent")
    Membership.create!(workspace: workspace, user: author, role: :member)
    Membership.create!(workspace: workspace, user: approver, role: :owner)

    agent_action = AgentActions::DraftCreator.new(
      workspace: workspace,
      actor: author,
      attributes: {
        title: "Draft release email",
        proposed_by: "manual",
        target_system: "gmail",
        draft_type: "email_draft",
        payload_json: {
          "to" => [ "team@example.com" ],
          "cc" => [],
          "subject" => "Release update",
          "body" => "Please review."
        }
      }
    ).call

    sign_in approver
    get workspace_notifications_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Agent draft awaiting approval")
    expect(response.body).to include(agent_action.title)
    expect(response.body).to include("Open draft")
  end

  it "renders workflow failure notifications in the inbox" do
    actor = User.create!(email: "notif-workflow-actor@example.com", password: "password123")
    workspace = Workspace.create!(name: "Notif Workflow", slug: "notif-workflow")
    Membership.create!(workspace: workspace, user: actor, role: :owner)
    workflow_run = WorkflowRun.create!(
      workspace: workspace,
      user: actor,
      workflow_kind: WorkflowRun::KIND_CREATE_TASK,
      status: WorkflowRun::STATUS_FAILED,
      trigger_source: "manual",
      queued_at: Time.current,
      finished_at: Time.current,
      confidence_score: 1.0,
      error_message: "Database lookup failed"
    )
    Notification.create!(
      workspace: workspace,
      actor: actor,
      recipient: actor,
      notifiable: workflow_run,
      notification_type: Notification::TYPE_WORKFLOW_FAILED,
      metadata: { "error_message" => "Database lookup failed" }
    )

    sign_in actor
    get workspace_notifications_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Workflow failed")
    expect(response.body).to include("Database lookup failed")
    expect(response.body).to include("Open workflow")
  end

  it "renders knowledge suggestion notifications in the inbox" do
    user = User.create!(email: "notif-suggestion@example.com", password: "password123")
    workspace = Workspace.create!(name: "Notif Suggestion", slug: "notif-suggestion")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    suggestion = KnowledgeSuggestion.create!(
      workspace: workspace,
      user: user,
      kind: KnowledgeSuggestion::KIND_PROACTIVE,
      status: KnowledgeSuggestion::STATUS_ACTIVE,
      title: "Escalate invoice delay",
      summary: "A supplier email now needs a follow-up. [1]",
      insights_json: [],
      task_suggestions_json: [],
      related_notes_json: [],
      sources_json: [],
      generated_at: Time.current,
      expires_at: 6.hours.from_now
    )
    Notification.create!(
      workspace: workspace,
      actor: user,
      recipient: user,
      notifiable: suggestion,
      notification_type: Notification::TYPE_KNOWLEDGE_SUGGESTION_READY,
      metadata: { "kind" => suggestion.kind }
    )

    sign_in user
    get workspace_notifications_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("New AI suggestion")
    expect(response.body).to include("Escalate invoice delay")
    expect(response.body).to include("Open suggestion")
    expect(response.body).to include("knowledge_suggestion_id=#{suggestion.id}")
    expect(response.body).to include("#knowledge-suggestion-#{suggestion.id}")
  end

  it "renders codex notifications with unavailable destinations as workspace links" do
    user = User.create!(email: "notif-codex-bad-destination@example.com", password: "password123")
    workspace = Workspace.create!(name: "Notif Codex Bad Destination", slug: "notif-codex-bad-destination")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    Notification.create!(
      workspace: workspace,
      actor: user,
      recipient: user,
      notification_type: Notification::TYPE_CODEX_REQUEST_COMPLETED,
      metadata: {
        "title" => "Codex request completed",
        "body" => "I finished the Tabulae check.",
        "path" => "/Users/errolschmidt/Documents/tabulae"
      }
    )

    sign_in user
    get workspace_notifications_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("I finished the Tabulae check.")
    expect(response.body).to include("The original destination is not available in Notae.")
    expect(response.body).to include("Open workspace")
    expect(response.body).to include(workspace_path(workspace.slug))
    expect(response.body).not_to include("/Users/errolschmidt/Documents/tabulae")
  end

  it "renders the daily summary agenda in the inbox" do
    user = User.create!(email: "notif-daily-summary@example.com", password: "password123")
    workspace = Workspace.create!(name: "Notif Daily Summary", slug: "notif-daily-summary")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    suggestion = KnowledgeSuggestion.create!(
      workspace: workspace,
      user: user,
      kind: KnowledgeSuggestion::KIND_DAILY_SUMMARY,
      status: KnowledgeSuggestion::STATUS_ACTIVE,
      title: "Daily morning summary",
      summary: "The day has two concrete meetings. [1]",
      insights_json: [],
      task_suggestions_json: [],
      related_notes_json: [],
      sources_json: [],
      generated_for_date: Date.new(2026, 4, 17),
      generated_at: Time.current
    )
    Notification.create!(
      workspace: workspace,
      actor: user,
      recipient: user,
      notifiable: suggestion,
      notification_type: Notification::TYPE_KNOWLEDGE_SUGGESTION_READY,
      metadata: {
        "kind" => suggestion.kind,
        "daily_agenda_items" => [
          { "time" => "09:00", "title" => "Stand-up" },
          { "time" => "11:30", "title" => "Client review" }
        ],
        "daily_agenda_total_count" => 3
      }
    )

    sign_in user
    get workspace_notifications_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Daily workspace brief ready")
    expect(response.body).to include("09:00")
    expect(response.body).to include("Stand-up")
    expect(response.body).to include("11:30")
    expect(response.body).to include("Client review")
    expect(response.body).to include("+1 more events today")
  end

  it "uses high-contrast notification link text in dark themes" do
    stylesheet = Rails.root.join("app/assets/stylesheets/application.css").read

    expect(stylesheet).to include("body.notae-theme-dark .notae-utility-link {\n  color: var(--notae-text-strong);")
    expect(stylesheet).to include("body.notae-theme-system .notae-utility-link {\n    color: var(--notae-text-strong);")
  end
end
