require "rails_helper"

RSpec.describe Search::KnowledgeSuggestionMaterializerService do
  it "creates a nota from a suggestion and marks it converted" do
    user = User.create!(email: "knowledge-materializer-nota@example.com", password: "password123")
    workspace = Workspace.create!(name: "Knowledge materializer", slug: "knowledge-materializer")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    suggestion = KnowledgeSuggestion.create!(
      workspace: workspace,
      user: user,
      kind: KnowledgeSuggestion::KIND_DAILY_SUMMARY,
      status: KnowledgeSuggestion::STATUS_ACTIVE,
      title: "Daily workspace brief",
      summary: "Review launch timing and confirm owners. [1]",
      insights_json: [ "The launch date remains provisional. [1]" ],
      task_suggestions_json: [
        { "title" => "Confirm launch owner", "owner" => "Alex", "rationale" => "There is no clear owner yet. [1]", "citation_indices" => [ 1 ] }
      ],
      related_notes_json: [
        { "title" => "Launch brief", "reason" => "Contains the current plan. [1]", "citation_indices" => [ 1 ] }
      ],
      sources_json: [
        { "index" => 1, "title" => "Launch brief", "url" => "/w/#{workspace.slug}/pages/example" }
      ],
      generated_for_date: Date.current,
      generated_at: Time.current
    )

    page = described_class.new(suggestion: suggestion, actor: user).create_nota!

    expect(page.title).to eq("Daily workspace brief notes")
    expect(page.page_kind).to eq("nota")
    expect(page.blocks.count).to eq(5)
    expect(page.blocks.order(:position).first.content_json.dig("content", 0, "content", 0, "text")).to include("Knowledge suggestion")

    suggestion.reload
    expect(suggestion.status).to eq(KnowledgeSuggestion::STATUS_CONVERTED)
    expect(suggestion.metadata_json["conversion_target_type"]).to eq("Page")
    expect(suggestion.metadata_json["conversion_target_id"]).to eq(page.id)
  end

  it "creates a task row in the nominated grid and seeds task template properties" do
    user = User.create!(email: "knowledge-materializer-task@example.com", password: "password123")
    workspace = Workspace.create!(name: "Knowledge task grid", slug: "knowledge-task-grid")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    database = Database.create!(workspace: workspace, name: "Tasks")
    status_property = DbProperty.create!(workspace: workspace, database: database, name: "Status", property_type: :select, position: 1)
    created_property = DbProperty.create!(workspace: workspace, database: database, name: "Date created", property_type: :date, position: 2)
    notes_property = DbProperty.create!(workspace: workspace, database: database, name: "Notes", property_type: :text, position: 3)
    DbProperty.create!(workspace: workspace, database: database, name: "Owner", property_type: :text, position: 4)

    suggestion = KnowledgeSuggestion.create!(
      workspace: workspace,
      user: user,
      kind: KnowledgeSuggestion::KIND_PROACTIVE,
      status: KnowledgeSuggestion::STATUS_ACTIVE,
      title: "Suggested next step",
      summary: "Follow up on the action items. [1]",
      task_suggestions_json: [
        { "title" => "Follow up on blockers", "owner" => "Errol", "rationale" => "The blockers are still open. [1]", "citation_indices" => [ 1 ] }
      ],
      generated_at: Time.current,
      expires_at: 4.hours.from_now
    )

    row = described_class.new(suggestion: suggestion, actor: user).create_task!(database: database, task_index: 0)

    expect(row.title).to eq("Follow up on blockers")
    expect(row.db_cells.find_by!(db_property: status_property).value_text).to eq("not started")
    expect(row.db_cells.find_by!(db_property: created_property).value_text).to eq(Date.current.iso8601)
    expect(row.db_cells.find_by!(db_property: notes_property).value_text).to eq("The blockers are still open. [1]")

    suggestion.reload
    expect(suggestion.status).to eq(KnowledgeSuggestion::STATUS_CONVERTED)
    expect(suggestion.metadata_json["conversion_target_type"]).to eq("DbRow")
    expect(suggestion.metadata_json["conversion_target_id"]).to eq(row.id)
  end
end
