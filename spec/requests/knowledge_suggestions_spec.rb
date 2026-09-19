require "rails_helper"

RSpec.describe "Knowledge suggestions", type: :request do
  let(:user) { User.create!(email: "knowledge-suggestion-ui@example.com", password: "password123") }
  let(:workspace) { Workspace.create!(name: "Knowledge UI", slug: "knowledge-ui") }

  before do
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user
  end

  def create_suggestion(kind: KnowledgeSuggestion::KIND_PROACTIVE, status: KnowledgeSuggestion::STATUS_ACTIVE)
    KnowledgeSuggestion.create!(
      workspace: workspace,
      user: user,
      kind: kind,
      status: status,
      title: kind == KnowledgeSuggestion::KIND_DAILY_SUMMARY ? "Daily workspace brief" : "Suggested next step",
      summary: "A suggestion grounded in sources. [1]",
      insights_json: [ "An insight with provenance. [1]" ],
      task_suggestions_json: [
        { "title" => "Triage outstanding blockers", "owner" => "Errol", "rationale" => "Several blockers remain open. [1]", "citation_indices" => [ 1 ] }
      ],
      related_notes_json: [ { "title" => "Planning note", "reason" => "Contains the current status. [1]" } ],
      sources_json: [ { "index" => 1, "title" => "Planning note", "url" => "/w/#{workspace.slug}/pages/abc" } ],
      generated_for_date: (Date.current if kind == KnowledgeSuggestion::KIND_DAILY_SUMMARY),
      generated_at: Time.current,
      expires_at: (4.hours.from_now if kind == KnowledgeSuggestion::KIND_PROACTIVE)
    )
  end

  it "shows the full suggestion as a concrete notification destination" do
    suggestion = create_suggestion
    Database.create!(workspace: workspace, name: "Tasks")

    get knowledge_suggestion_path(workspace_slug: workspace.slug, id: suggestion.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Suggested next step")
    expect(response.body).to include("A suggestion grounded in sources. [1]")
    expect(response.body).to include("Triage outstanding blockers")
    expect(response.body).to include("Notifications")
    expect(response.body).to include("Workspace home")
  end

  it "dismisses an active suggestion" do
    suggestion = create_suggestion

    post dismiss_knowledge_suggestion_path(workspace_slug: workspace.slug, id: suggestion.id)

    expect(response).to redirect_to(workspace_path(workspace.slug))
    expect(suggestion.reload.status).to eq(KnowledgeSuggestion::STATUS_DISMISSED)
    expect(flash[:notice]).to eq("Suggestion dismissed.")
  end

  it "converts a suggestion into a nota" do
    suggestion = create_suggestion

    post convert_to_nota_knowledge_suggestion_path(workspace_slug: workspace.slug, id: suggestion.id)

    page = workspace.pages.order(:created_at).last
    expect(response).to redirect_to(page_path(workspace_slug: workspace.slug, id: page.id))
    expect(page.title).to eq("Suggested next step notes")
    expect(page.blocks).not_to be_empty
    expect(suggestion.reload.status).to eq(KnowledgeSuggestion::STATUS_CONVERTED)
  end

  it "converts a suggestion into a task in the nominated grid" do
    suggestion = create_suggestion
    database = Database.create!(workspace: workspace, name: "Tasks")
    status_property = DbProperty.create!(workspace: workspace, database: database, name: "Status", property_type: :select, position: 1)
    DbProperty.create!(workspace: workspace, database: database, name: "Date created", property_type: :date, position: 2)
    DbProperty.create!(workspace: workspace, database: database, name: "Notes", property_type: :text, position: 3)

    post convert_to_task_knowledge_suggestion_path(workspace_slug: workspace.slug, id: suggestion.id),
         params: { knowledge_suggestion: { database_id: database.id, task_index: 0 } }

    row = database.db_rows.order(:created_at).last
    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id, anchor: "row_#{row.id}"))
    expect(row.title).to eq("Triage outstanding blockers")
    expect(row.db_cells.find_by!(db_property: status_property).value_text).to eq("not started")
    expect(suggestion.reload.status).to eq(KnowledgeSuggestion::STATUS_CONVERTED)
  end

  it "refreshes a suggestion through the persistence service" do
    suggestion = create_suggestion
    persisted = create_suggestion(status: KnowledgeSuggestion::STATUS_ACTIVE)
    service = instance_double(Search::PersistKnowledgeSuggestionService, call: persisted)

    expect(Search::PersistKnowledgeSuggestionService).to receive(:new)
      .with(user: user, workspace: workspace, kind: suggestion.kind, force: true)
      .and_return(service)

    post refresh_knowledge_suggestion_path(workspace_slug: workspace.slug, id: suggestion.id)

    expect(response).to redirect_to(workspace_path(workspace.slug))
    expect(suggestion.reload.status).to eq(KnowledgeSuggestion::STATUS_DISMISSED)
    expect(flash[:notice]).to eq("Suggestion refreshed.")
  end
end
