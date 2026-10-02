require "rails_helper"

RSpec.describe "Removed features", type: :request do
  include ActiveJob::TestHelper

  before do
    clear_enqueued_jobs
  end

  it "does not expose Epistularium routes or navigation" do
    user = User.create!(email: "removed-mail@example.com", password: "password123")
    workspace = Workspace.create!(name: "No mail", slug: "no-mail")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    expect do
      Rails.application.routes.recognize_path("/w/#{workspace.slug}/epistularium", method: :get)
    end.to raise_error(ActionController::RoutingError)

    sign_in user
    get workspace_path(workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Epistularium")
    expect(response.body).not_to include("/w/#{workspace.slug}/epistularium")
  end

  it "keeps the AI rail while excluding legacy proactive suggestions" do
    user = User.create!(email: "removed-proactive@example.com", password: "password123")
    workspace = Workspace.create!(name: "No proactive", slug: "no-proactive")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    KnowledgeSuggestion.create!(
      workspace: workspace,
      user: user,
      kind: KnowledgeSuggestion::KIND_PROACTIVE,
      status: KnowledgeSuggestion::STATUS_ACTIVE,
      title: "Legacy proactive suggestion",
      summary: "This should no longer appear in the AI rail.",
      generated_at: Time.current,
      expires_at: 4.hours.from_now
    )

    sign_in user
    get workspace_ai_assistant_panel_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Notae AI")
    expect(response.body).to include("Ask Notae to find, answer, create, or change something")
    expect(response.body).not_to include("Legacy proactive suggestion")
    expect(enqueued_jobs).not_to include(
      a_hash_including(
        job: Search::GenerateKnowledgeSuggestionJob,
        args: [ user.id, workspace.id, KnowledgeSuggestion::KIND_PROACTIVE ]
      )
    )
  end
end
