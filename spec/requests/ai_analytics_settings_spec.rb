require "rails_helper"

RSpec.describe "AI Analytics settings", type: :request do
  it "renders 7/30 day trends and operation breakdown" do
    user = User.create!(email: "ai-analytics-settings@example.com", password: "password123")
    workspace = Workspace.create!(name: "AI Analytics Settings", slug: "ai-analytics-settings")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    KnowledgeSuggestion.create!(
      workspace: workspace,
      user: user,
      kind: KnowledgeSuggestion::KIND_PROACTIVE,
      status: KnowledgeSuggestion::STATUS_CONVERTED,
      title: "Daily quality signal",
      summary: "Converted suggestion",
      generated_at: Time.current,
      insights_json: [],
      task_suggestions_json: [],
      related_notes_json: [],
      sources_json: []
    )
    AgentAction.create!(
      workspace: workspace,
      user: user,
      title: "Approved action",
      proposed_by: "manual",
      target_system: "gmail",
      draft_type: "email_draft",
      status: AgentAction::STATUS_APPROVED,
      approval_required: true,
      dry_run: true,
      payload_json: {
        "to" => [ "team@example.com" ],
        "cc" => [],
        "subject" => "Approved",
        "body" => "Approved."
      }
    )
    WorkflowRun.create!(
      workspace: workspace,
      user: user,
      workflow_kind: WorkflowRun::KIND_CREATE_NOTA,
      status: WorkflowRun::STATUS_FAILED,
      trigger_source: "manual",
      queued_at: Time.current,
      finished_at: Time.current,
      confidence_score: 1.0,
      error_message: "Create note failed"
    )

    first_log = AiUsageLog.create!(
      user: user,
      workspace: workspace,
      operation: AiUsageLog::OP_SEARCH_ANSWER,
      model: "gpt-4o-mini",
      prompt_tokens: 100,
      completion_tokens: 25,
      total_tokens: 125,
      estimated_cost_usd: 0.03
    )
    first_log.update_columns(created_at: 2.days.ago, updated_at: 2.days.ago)

    second_log = AiUsageLog.create!(
      user: user,
      workspace: workspace,
      operation: AiUsageLog::OP_ASSISTANT_QUERY,
      model: "gpt-4o-mini",
      prompt_tokens: 240,
      completion_tokens: 80,
      total_tokens: 320,
      estimated_cost_usd: 0.09
    )
    second_log.update_columns(created_at: 1.day.ago, updated_at: 1.day.ago)

    AiUsageLog.create!(
      user: user,
      workspace: workspace,
      operation: AiUsageLog::OP_KNOWLEDGE_SUGGESTION_MISS,
      model: "gpt-4.1-mini",
      prompt_tokens: 0,
      completion_tokens: 0,
      total_tokens: 0,
      estimated_cost_usd: 0,
      metadata: { reason: "no_recent_changes" }
    )
    AiUsageLog.create!(
      user: user,
      workspace: workspace,
      operation: AiUsageLog::OP_KNOWLEDGE_SUGGESTION_FAILURE,
      model: "gpt-4.1-mini",
      prompt_tokens: 0,
      completion_tokens: 0,
      total_tokens: 0,
      estimated_cost_usd: 0,
      metadata: { reason: "provider_error", error_message: "upstream unavailable" }
    )

    sign_in user
    get workspace_ai_analytics_settings_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("AI Use")
    expect(response.body).not_to include(">AI Analytics<")
    expect(response.body).to include("AI usage trends")
    expect(response.body).to include("Past 7 days")
    expect(response.body).to include("Past 30 days")
    expect(response.body).to include("Operation breakdown")
    expect(response.body).to include("Assistant query generation")
    expect(response.body).to include("Search answer generation")
    expect(response.body).to include("Meeting diarization")
    expect(response.body).to include("Workflow Metrics")
    expect(response.body).to include("Suggestion health")
    expect(response.body).to include("Knowledge suggestion miss")
    expect(response.body).to include("Knowledge suggestion failure")
    expect(response.body).to include("upstream unavailable")
    expect(response.body).to include("Automation Safety")
    expect(response.body).to include("Error Monitoring")
    expect(response.body).to include("Create note failed")
    expect(response.body).to include("Inspect workflow")
  end

  it "updates the automation kill switch for platform admins" do
    user = User.create!(email: "ai-analytics-kill-switch@example.com", password: "password123", super_admin: true)
    workspace = Workspace.create!(name: "AI Analytics Kill Switch", slug: "ai-analytics-kill-switch")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    patch workspace_ai_analytics_settings_path(workspace_slug: workspace.slug),
          params: { automation_control: { enabled: "0", pause_reason: "Maintenance window" } }

    expect(response).to redirect_to(workspace_ai_analytics_settings_path(workspace_slug: workspace.slug))
    control = AutomationControl.current
    expect(control.enabled).to eq(false)
    expect(control.pause_reason).to eq("Maintenance window")
  end

  it "rejects automation kill switch updates for non-platform admins" do
    user = User.create!(email: "ai-analytics-kill-switch-denied@example.com", password: "password123")
    workspace = Workspace.create!(name: "AI Analytics Kill Switch Denied", slug: "ai-analytics-kill-switch-denied")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    patch workspace_ai_analytics_settings_path(workspace_slug: workspace.slug),
          params: { automation_control: { enabled: "0", pause_reason: "Malicious pause" } }

    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to eq("You are not authorized to perform this action.")
    expect(AutomationControl.current.enabled).to eq(true)
  end

  it "returns turbo stream updates for automation safety changes" do
    user = User.create!(email: "ai-analytics-turbo@example.com", password: "password123", super_admin: true)
    workspace = Workspace.create!(name: "AI Analytics Turbo", slug: "ai-analytics-turbo")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    patch workspace_ai_analytics_settings_path(workspace_slug: workspace.slug),
          params: { automation_control: { enabled: "0", pause_reason: "Ops freeze" } },
          headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include('turbo-stream action="replace" target="settings_flash_messages"')
    expect(response.body).to include('turbo-stream action="replace" target="ai_analytics_settings_content"')
    expect(response.body).to include("Automation kill switch enabled.")
  end

  it "hides AI cost details in production while keeping token usage visible" do
    user = User.create!(email: "ai-analytics-production@example.com", password: "password123")
    workspace = Workspace.create!(name: "AI Analytics Production", slug: "ai-analytics-production")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    AiUsageLog.create!(
      user: user,
      workspace: workspace,
      operation: AiUsageLog::OP_SEARCH_ANSWER,
      model: "gpt-4o-mini",
      prompt_tokens: 100,
      completion_tokens: 50,
      total_tokens: 150,
      estimated_cost_usd: 0.04
    )
    sign_in user

    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))

    get workspace_ai_analytics_settings_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("150 tokens")
    expect(response.body).not_to include("<th>Cost</th>")
    expect(response.body).not_to include("$0.04")
  end
end
