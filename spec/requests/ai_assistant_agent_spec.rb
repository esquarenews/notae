require "rails_helper"

RSpec.describe "AI Assistant agent", type: :request do
  let(:user) do
    User.create!(
      email: "ai-agent-request@example.com",
      password: "password123",
      time_zone: "Australia/Melbourne"
    )
  end
  let(:workspace) { Workspace.create!(name: "AI Agent Request", slug: "ai-agent-request") }
  let(:page) { Page.create!(workspace: workspace, created_by: user, title: "Old document title") }

  before do
    Membership.create!(workspace: workspace, user: user, role: :owner)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return("sk-server-test")
    allow(Search::AiBudgetGuard).to receive(:within_daily_budget?).and_return(true)
    allow(Search::AiRateLimiter).to receive(:allowed?).and_return(true)
    route = Search::AssistantModelRouter::Route.new(
      tier: "terra",
      model: "gpt-5.6-terra",
      reasoning_effort: "medium",
      usage: Openai::ResponsesClient.default_usage
    )
    allow_any_instance_of(Search::AssistantModelRouter).to receive(:call).and_return(route)
    sign_in user
  end

  after do
    AutomationControl.current.resume!
  end

  it "executes an authorized plain-language document change without creating an approval draft" do
    allow(Openai::ResponsesClient).to receive(:create).and_return(
      {
        id: "resp_rename_tool",
        text: "",
        function_calls: [
          {
            name: "update_nota",
            call_id: "call_rename",
            arguments: {
              "page_id" => page.id,
              "title" => "Clear launch brief",
              "body" => "",
              "body_mode" => "keep"
            }
          }
        ],
        usage: { prompt_tokens: 70, completion_tokens: 20, total_tokens: 90 },
        sources: []
      },
      {
        id: "resp_rename_final",
        text: "Renamed this document to Clear launch brief.",
        function_calls: [],
        usage: { prompt_tokens: 25, completion_tokens: 12, total_tokens: 37 },
        sources: []
      }
    )

    expect {
      post workspace_ai_assistant_path(workspace_slug: workspace.slug),
           params: {
             ai_assistant: {
               prompt: "This title is vague. Rename this document to Clear launch brief.",
               scope: Search::AssistantQueryService::SCOPE_DOCUMENT,
               current_page_id: page.id
             }
           },
           headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }
    }.to change(AiConversation, :count).by(1).and change(WorkflowRun, :count).by(1).and change(AgentAction, :count).by(0)

    expect(response).to have_http_status(:ok)
    expect(page.reload.title).to eq("Clear launch brief")
    expect(response.body).to include("Renamed this document to Clear launch brief.")
    expect(response.body).to include("Done · Clear launch brief")

    conversation = AiConversation.order(:created_at).last
    expect(conversation.model).to eq("gpt-5.6-terra")
    expect(conversation.thread_id).to be_present
    expect(conversation.sources.map { |source| source["kind"] }).to include("Completed action")
  end

  it "uses web evidence and then creates a summarized Nota in one uninterrupted request" do
    allow(Openai::ResponsesClient).to receive(:create).and_return(
      {
        id: "resp_article_tool",
        text: "",
        function_calls: [
          {
            name: "create_nota",
            call_id: "call_create_nota",
            arguments: {
              "workspace_id" => "",
              "title" => "Article summary",
              "body" => "## Summary\n\nThe article argues for smaller, verifiable releases."
            }
          }
        ],
        usage: { prompt_tokens: 90, completion_tokens: 30, total_tokens: 120 },
        sources: [ { title: "Original article", url: "https://example.com/article" } ]
      },
      {
        id: "resp_article_final",
        text: "Created Article summary from the linked article.",
        function_calls: [],
        usage: { prompt_tokens: 30, completion_tokens: 12, total_tokens: 42 },
        sources: []
      }
    )

    expect {
      post workspace_ai_assistant_path(workspace_slug: workspace.slug),
           params: {
             ai_assistant: {
               prompt: "Summarise https://example.com/article into a new Nota here.",
               scope: Search::AssistantQueryService::SCOPE_WORKSPACE
             }
           },
           headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }
    }.to change(Page, :count).by(1).and change(AgentAction, :count).by(0)

    created_page = Page.order(:created_at).last
    expect(created_page.title).to eq("Article summary")
    expect(Pages::MarkdownExportService.call(page: created_page).markdown).to include("smaller, verifiable releases")
    expect(response.body).to include("Created Article summary")
    expect(response.body).to include("Done · Article summary")
    expect(response.body).to include("Original article")
    expect(response.body).to include("notae-ai-web-sources")
  end

  it "starts a clean chat thread while retaining prior conversations in history" do
    AiConversation.create!(
      user: user,
      workspace: workspace,
      page: page,
      thread_id: "11111111-1111-4111-8111-111111111111",
      scope: Search::AssistantQueryService::SCOPE_DOCUMENT,
      prompt: "Old thread prompt",
      answer: "Old thread answer",
      status: AiConversation::STATUS_SUCCESS,
      sources: []
    )

    get workspace_ai_assistant_panel_path(workspace_slug: workspace.slug, current_page_id: page.id)
    expect(response.body).not_to include("Old thread prompt")
    expect(response.body).to include("Find it. Understand it. Get it done.")
    expect(response.body).to include("Whole app")

    post workspace_ai_assistant_new_chat_path(workspace_slug: workspace.slug),
         params: { current_page_id: page.id },
         headers: { "Turbo-Frame" => "ai_rail_panel" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Ask Notae to find, answer, create, or change something")
    expect(AiConversation.where(prompt: "Old thread prompt")).to exist
  end

  it "keeps proactive suggestions actionable inside the rail" do
    KnowledgeSuggestion.create!(
      workspace: workspace,
      user: user,
      kind: KnowledgeSuggestion::KIND_PROACTIVE,
      status: KnowledgeSuggestion::STATUS_ACTIVE,
      title: "Prepare the release note",
      summary: "The launch decision is ready to document. [1]",
      insights_json: [ "The final date is confirmed. [1]" ],
      task_suggestions_json: [ { "title" => "Draft the release note", "rationale" => "The source is final. [1]" } ],
      sources_json: [ { "index" => 1, "title" => "Launch brief", "url" => "/w/#{workspace.slug}/pages/source" } ],
      generated_at: Time.current,
      expires_at: 4.hours.from_now
    )

    get workspace_ai_assistant_panel_path(workspace_slug: workspace.slug, current_page_id: page.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Proactive suggestion")
    expect(response.body).to include("Prepare the release note")
    expect(response.body).to include("Create Nota")
    expect(response.body).to include("Refresh")
    expect(response.body).to include("Dismiss")
  end
end
