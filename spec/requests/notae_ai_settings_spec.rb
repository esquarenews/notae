require "rails_helper"

RSpec.describe "Notae AI settings", type: :request do
  it "renders the loader preview and style library" do
    user = User.create!(email: "notae-ai-settings-owner@example.com", password: "password123", ai_loader_style: "neon_mesh")
    workspace = Workspace.create!(name: "Notae AI settings", slug: "notae-ai-settings")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    get workspace_notae_ai_settings_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Notae AI loader")
    expect(response.body).to include("Static state")
    expect(response.body).to include("Loading state")
    expect(response.body).to include("Style library")
    expect(response.body).to include("AI guardrails")
    expect(response.body).to include("Halo Relay")
    expect(response.body).to include("Mirror Sweep")
    expect(response.body).to include("Synapse Bloom")
    expect(response.body).to include("Plasma Core")
    expect(response.body).to include("Tidal Pulse")
    expect(response.body).to include("notae-ai-loader")
    expect(response.body).to include("is-hover-animate")
    expect(response.body).to include("Hover to preview animation.")
    expect(response.body).to include("notae-ai-loader-shell")
    expect(response.body).to include("notae-ai-loader-beam")
    expect(response.body).to include("p-16")
    expect(response.body).to include("notae-ai-loader-options-grid is-two-column")
    expect(response.body).to include("This document only")
    expect(response.body).to include("This workspace only")
    expect(response.body).to include("Whole account")
    expect(response.body).to include("Agent Action Policy")
    expect(response.body).to include("notae-settings-nav-item active")
  end

  it "updates the selected Notae AI loader style for the current user" do
    user = User.create!(email: "notae-ai-settings-update@example.com", password: "password123")
    workspace = Workspace.create!(name: "Notae AI settings update", slug: "notae-ai-settings-update")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    patch workspace_notae_ai_settings_path(workspace_slug: workspace.slug),
          params: { user: { ai_loader_style: "neural_network" } }

    expect(response).to redirect_to(workspace_notae_ai_settings_path(workspace_slug: workspace.slug))
    expect(user.reload.ai_loader_style).to eq("neural_network")
  end

  it "shows today's AI usage totals and guardrail status in the right sidebar" do
    original_budget = Rails.application.config.x.ai_search.daily_budget_usd
    Rails.application.config.x.ai_search.daily_budget_usd = 1.0

    user = User.create!(email: "notae-ai-settings-usage@example.com", password: "password123")
    workspace = Workspace.create!(name: "Notae AI usage", slug: "notae-ai-usage")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    AiUsageLog.create!(
      user: user,
      workspace: workspace,
      operation: AiUsageLog::OP_SEARCH_ANSWER,
      model: "gpt-4o-mini",
      prompt_tokens: 500,
      completion_tokens: 120,
      total_tokens: 620,
      estimated_cost_usd: 0.24
    )
    AiUsageLog.create!(
      user: user,
      workspace: workspace,
      operation: AiUsageLog::OP_MEETING_TRANSCRIPTION,
      model: "gpt-4o-transcribe-diarize",
      prompt_tokens: 300,
      completion_tokens: 90,
      total_tokens: 390,
      estimated_cost_usd: 0.08
    )
    AiUsageLog.create!(
      user: user,
      workspace: workspace,
      operation: AiUsageLog::OP_MEETING_SUMMARY,
      model: "gpt-4.1",
      prompt_tokens: 80,
      completion_tokens: 20,
      total_tokens: 100,
      estimated_cost_usd: 0.06
    )
    sign_in user

    get workspace_notae_ai_settings_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("notae-ai-usage-card")
    expect(response.body).to include("Today usage")
    expect(response.body).to include("1,110")
    expect(response.body).to include("$0.38")
    expect(response.body).to include("Guardrails")
    expect(response.body).to include("Budget:")
    expect(response.body).to include("Available")
    expect(response.body).to include("left")
  ensure
    Rails.application.config.x.ai_search.daily_budget_usd = original_budget
  end

  it "updates AI guardrail controls for the current user" do
    user = User.create!(email: "notae-ai-settings-guardrails@example.com", password: "password123")
    workspace = Workspace.create!(name: "Notae AI guardrails update", slug: "notae-ai-guardrails-update")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    patch workspace_notae_ai_settings_path(workspace_slug: workspace.slug),
          params: {
            user: {
              ai_search_daily_budget_usd: "2.25",
              ai_search_semantic_rate_limit_per_minute: "15",
              ai_search_answer_rate_limit_per_minute: "8"
            }
          }

    expect(response).to redirect_to(workspace_notae_ai_settings_path(workspace_slug: workspace.slug))
    user.reload
    expect(user.ai_search_daily_budget_usd.to_f).to eq(2.25)
    expect(user.ai_search_semantic_rate_limit_per_minute).to eq(15)
    expect(user.ai_search_answer_rate_limit_per_minute).to eq(8)
  end

  it "updates the workspace agent action policy for owners" do
    user = User.create!(email: "notae-ai-settings-policy@example.com", password: "password123")
    workspace = Workspace.create!(name: "Notae AI policy", slug: "notae-ai-policy")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    patch workspace_notae_ai_settings_path(workspace_slug: workspace.slug),
          params: {
            agent_policy: {
              approval_required: "1",
              dry_run_required: "1",
              max_estimated_cost_usd: "0.50",
              allow_internal_automation: "1",
              automation_retry_limit: "3",
              automation_confidence_threshold: "0.80",
              allowed_target_systems_json: %w[gmail github],
              allowed_draft_types_json: %w[email_draft github_comment_draft],
              allowed_lifecycle_operations_json: %w[draft update approve reject request_changes],
              allowed_internal_actions_json: %w[create_nota create_task],
              author_roles_json: %w[member owner automation_agent],
              approver_roles_json: %w[owner]
            }
          }

    expect(response).to redirect_to(workspace_notae_ai_settings_path(workspace_slug: workspace.slug))
    policy = workspace.reload.agent_policy
    expect(policy.allowed_target_systems).to eq(%w[gmail github])
    expect(policy.allowed_internal_actions).to eq(%w[create_nota create_task])
    expect(policy.approver_roles).to eq(%w[owner])
    expect(policy.automation_retry_limit).to eq(3)
    expect(policy.automation_confidence_threshold.to_f).to eq(0.8)
    expect(policy.max_estimated_cost_usd.to_f).to eq(0.5)
  end
end
