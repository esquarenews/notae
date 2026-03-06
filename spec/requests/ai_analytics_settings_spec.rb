require "rails_helper"

RSpec.describe "AI Analytics settings", type: :request do
  it "renders 7/30 day trends and operation breakdown" do
    user = User.create!(email: "ai-analytics-settings@example.com", password: "password123")
    workspace = Workspace.create!(name: "AI Analytics Settings", slug: "ai-analytics-settings")
    Membership.create!(workspace: workspace, user: user, role: :owner)

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

    sign_in user
    get workspace_ai_analytics_settings_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("AI usage trends")
    expect(response.body).to include("Past 7 days")
    expect(response.body).to include("Past 30 days")
    expect(response.body).to include("Operation breakdown")
    expect(response.body).to include("Assistant query generation")
    expect(response.body).to include("Search answer generation")
    expect(response.body).to include("Meeting diarization")
  end
end
