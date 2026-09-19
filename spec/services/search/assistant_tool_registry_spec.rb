require "rails_helper"

RSpec.describe Search::AssistantToolRegistry do
  let(:user) { User.create!(email: "assistant-tools@example.com", password: "password123", time_zone: "Australia/Melbourne") }
  let(:workspace) { Workspace.create!(name: "Assistant Tools", slug: "assistant-tools") }

  before do
    Membership.create!(workspace: workspace, user: user, role: :owner)
  end

  after do
    AutomationControl.current.resume!
  end

  it "exposes reusable resource tools instead of example-specific prompt handlers" do
    registry = described_class.new(
      user: user,
      workspace: workspace,
      selected_scope: Search::AssistantQueryService::SCOPE_AUTO
    )

    names = registry.definitions.map { |definition| definition.fetch(:name) }
    expect(names).to contain_exactly(
      "search_notae",
      "read_nota",
      "list_notae_resources",
      "update_nota",
      "create_nota",
      "create_database",
      "create_database_row",
      "create_calendar_event"
    )
    expect(registry.definitions).to all(include(type: "function", strict: true))
    expect(registry.definitions).to all(satisfy { |definition| definition.dig(:parameters, :additionalProperties) == false })
  end

  it "creates a generic list and all requested items immediately without an AgentAction approval" do
    registry = described_class.new(
      user: user,
      workspace: workspace,
      selected_scope: Search::AssistantQueryService::SCOPE_WORKSPACE
    )

    expect {
      @result = registry.call(
        name: "create_database",
        arguments: {
          workspace_id: "",
          name: "Launch checklist",
          description: "Things needed before release",
          properties: [
            { name: "Status", type: "select", options: [ "Not started", "Done" ] },
            { name: "Owner", type: "text", options: [] }
          ],
          rows: [
            {
              title: "Prepare screenshots",
              cells: [
                { property: "Status", value: "Not started" },
                { property: "Owner", value: "Sam" }
              ]
            },
            {
              title: "Publish notes",
              cells: [ { property: "Status", value: "Done" } ]
            }
          ]
        }
      )
    }.to change(Database, :count).by(1).and change(DbRow, :count).by(2).and change(AgentAction, :count).by(0)

    expect(@result).to include(ok: true, status: WorkflowRun::STATUS_SUCCEEDED, action: WorkflowRun::KIND_CREATE_DATABASE)
    database = Database.find(@result.dig(:result, "target_id"))
    expect(database.db_rows.order(:created_at).pluck(:title)).to eq([ "Prepare screenshots", "Publish notes" ])
    expect(registry.sources).to include(hash_including(kind: "Completed action", title: "Launch checklist"))
  end

  it "deduplicates an identical write tool call within one assistant run" do
    registry = described_class.new(
      user: user,
      workspace: workspace,
      selected_scope: Search::AssistantQueryService::SCOPE_WORKSPACE
    )
    arguments = {
      workspace_id: "",
      title: "Decision record",
      body: "## Decision\n\nUse the new launch plan."
    }

    expect do
      first = registry.call(name: "create_nota", arguments: arguments)
      second = registry.call(name: "create_nota", arguments: arguments)
      expect(second).to eq(first)
    end.to change(Page, :count).by(1)
  end

  it "enforces document scope when reading an exact page id" do
    current_page = Page.create!(workspace: workspace, created_by: user, title: "Current")
    other_page = Page.create!(workspace: workspace, created_by: user, title: "Other")
    registry = described_class.new(
      user: user,
      workspace: workspace,
      selected_scope: Search::AssistantQueryService::SCOPE_DOCUMENT,
      current_page: current_page
    )

    result = registry.call(name: "read_nota", arguments: { page_id: other_page.id })

    expect(result).to eq(ok: false, error: "That Notae item is not available in the selected scope.")
    expect(registry.sources).to be_empty
  end
end
