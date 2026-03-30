require "rails_helper"

RSpec.describe "AI Assistant", type: :request do
  it "returns a turbo-stream sidebar update with answer and stores the conversation history" do
    user = User.create!(email: "ai-assistant-request@example.com", password: "password123", openai_api_key: "sk-test")
    workspace = Workspace.create!(name: "AI Assistant Request", slug: "ai-assistant-request")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    page = Page.create!(workspace: workspace, created_by: user, title: "Mac Page")
    SearchChunk.create!(
      workspace: workspace,
      source_type: SearchChunk::SOURCE_PAGE,
      source_id: page.id,
      page: page,
      chunk_index: 0,
      text: "Mac appears in this workspace context",
      token_count: 6,
      content_hash: "assistant-request-hash",
      embedding: [ 0.4, 0.8 ],
      embedding_model: SearchChunk::EMBEDDING_MODEL
    )

    allow(Openai::ResponsesClient).to receive(:generate_text_with_usage).and_return(
      {
        text: "Yes, Mac is mentioned [1].",
        usage: { prompt_tokens: 70, completion_tokens: 18, total_tokens: 88 }
      }
    )

    sign_in user
    expect {
      post workspace_ai_assistant_path(workspace_slug: workspace.slug),
           params: { ai_assistant: { prompt: "Is Mac mentioned?", scope: "this-will-fallback", current_page_id: page.id } },
           headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }
    }.to change(AiConversation, :count).by(1)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("turbo-stream")
    expect(response.body).to include('action="replace" target="ai_rail_panel"')
    expect(response.body).to include("ai_rail_panel")
    expect(response.body).to include("ai_conversation_history_list")
    expect(response.body).to include("notae-ai-thread")
    expect(response.body).to include("Is Mac mentioned?")
    expect(response.body).to include("Copy result")
    expect(response.body).to include("Sources")
    expect(response.body).to include("Hide")
    expect(response.body).to include("data-turbo-frame=\"_top\"")
    expect(response.body).to include("Yes, Mac is mentioned")

    conversation = AiConversation.order(:created_at).last
    expect(conversation.prompt).to eq("Is Mac mentioned?")
    expect(conversation.answer).to include("Yes, Mac is mentioned")
    expect(conversation.status).to eq(AiConversation::STATUS_SUCCESS)
    expect(conversation.model).to eq(Search::AssistantQueryService::SEARCH_MODEL)
  end

  it "renders the ai rail frame for html turbo-frame submissions" do
    user = User.create!(email: "ai-assistant-frame-request@example.com", password: "password123")
    workspace = Workspace.create!(name: "AI Assistant Frame Request", slug: "ai-assistant-frame-request")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    sign_in user
    expect {
      post workspace_ai_assistant_path(workspace_slug: workspace.slug),
           params: { ai_assistant: { prompt: "Frame fallback prompt", scope: Search::AssistantQueryService::SCOPE_AUTO } },
           headers: {
             "ACCEPT" => "text/html,application/xhtml+xml",
             "Turbo-Frame" => "ai_rail_panel"
           }
    }.to change(AiConversation, :count).by(1)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/html")
    expect(response.body).to include('<turbo-frame id="ai_rail_panel">')
    expect(response.body).to include("Frame fallback prompt")
    expect(response.body).to include("Configure an OpenAI key in Settings &gt; Connections first.")
  end

  it "renders the lazy-loaded ai rail panel on demand" do
    user = User.create!(email: "ai-assistant-panel-request@example.com", password: "password123")
    workspace = Workspace.create!(name: "AI Assistant Panel Request", slug: "ai-assistant-panel-request")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    page = Page.create!(workspace: workspace, created_by: user, title: "Panel page")

    sign_in user
    get workspace_ai_assistant_panel_path(workspace_slug: workspace.slug, current_page_id: page.id)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/html")
    expect(response.body).to include('<turbo-frame id="ai_rail_panel">')
    expect(response.body).to include("notae-ai-prompt-input")
    expect(response.body).to include(%(value="#{page.id}"))
  end

  it "falls back to a notice instead of raising when the assistant service crashes" do
    user = User.create!(email: "ai-assistant-service-crash@example.com", password: "password123", openai_api_key: "sk-test")
    workspace = Workspace.create!(name: "AI Assistant Service Crash", slug: "ai-assistant-service-crash")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    sign_in user
    allow_any_instance_of(Search::AssistantQueryService).to receive(:call).and_raise(EOFError, "connection reset by peer")

    expect {
      post workspace_ai_assistant_path(workspace_slug: workspace.slug),
           params: { ai_assistant: { prompt: "Will this crash?", scope: Search::AssistantQueryService::SCOPE_AUTO } },
           headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }
    }.to change(AiConversation, :count).by(1)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Notae AI request failed. Please retry.")
    expect(AiConversation.order(:created_at).last.answer).to eq("Notae AI request failed. Please retry.")
  end

  it "shows a no-context notice for document scope without current document and stores notice history" do
    user = User.create!(email: "ai-assistant-no-context@example.com", password: "password123", openai_api_key: "sk-test")
    workspace = Workspace.create!(name: "AI Assistant No Context", slug: "ai-assistant-no-context")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    sign_in user
    expect {
      post workspace_ai_assistant_path(workspace_slug: workspace.slug),
           params: { ai_assistant: { prompt: "Summarise this document", scope: Search::AssistantQueryService::SCOPE_DOCUMENT } },
           headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }
    }.to change(AiConversation, :count).by(1)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("could not find enough context")

    conversation = AiConversation.order(:created_at).last
    expect(conversation.status).to eq(AiConversation::STATUS_NOTICE)
    expect(conversation.answer).to include("could not find enough context")
  end

  it "returns compose responses with insert payload metadata for editor insertion fallback" do
    user = User.create!(email: "ai-assistant-compose-request@example.com", password: "password123", openai_api_key: "sk-test")
    workspace = Workspace.create!(name: "AI Assistant Compose Request", slug: "ai-assistant-compose-request")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    page = Page.create!(workspace: workspace, created_by: user, title: "Draft page")
    block = Block.create!(
      workspace: workspace,
      page: page,
      created_by: user,
      block_type: "paragraph",
      content_json: {
        "type" => "doc",
        "content" => [
          {
            "type" => "paragraph",
            "content" => [ { "type" => "text", "text" => "Existing draft context" } ]
          }
        ]
      }
    )

    expect(Openai::ResponsesClient).to receive(:generate_text_with_usage) do |args|
      expect(args[:model]).to eq("gpt-4.1-mini")
      {
        text: "A polished launch paragraph for insertion.",
        usage: { prompt_tokens: 65, completion_tokens: 22, total_tokens: 87 }
      }
    end

    sign_in user
    post workspace_ai_assistant_path(workspace_slug: workspace.slug),
         params: {
           ai_assistant: {
             prompt: "Write a polished paragraph for this section.",
             scope: Search::AssistantQueryService::SCOPE_DOCUMENT,
             intent: Search::AssistantQueryService::INTENT_COMPOSE,
             current_page_id: page.id,
             target_block_id: block.id
           }
         },
         headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("data-ai-insert-text")
    expect(response.body).to include("A polished launch paragraph for insertion.")
    expect(response.body).to include(block.id)
    expect(AiConversation.order(:created_at).last.answer).to include("polished launch paragraph")
  end

  it "creates agent action drafts from AI rail prompts and stores suggestion history" do
    user = User.create!(email: "ai-assistant-draft-action@example.com", password: "password123", openai_api_key: "sk-test")
    workspace = Workspace.create!(name: "AI Assistant Draft Action", slug: "ai-assistant-draft-action")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    page = Page.create!(workspace: workspace, created_by: user, title: "Launch brief")
    SearchChunk.create!(
      workspace: workspace,
      source_type: SearchChunk::SOURCE_PAGE,
      source_id: page.id,
      page: page,
      chunk_index: 0,
      text: "Launch slipped by two days and the team wants an email update.",
      token_count: 12,
      content_hash: "assistant-draft-action-hash",
      embedding: [ 0.3, 0.6 ],
      embedding_model: SearchChunk::EMBEDDING_MODEL
    )

    expect(Openai::ResponsesClient).to receive(:generate_text_with_usage) do |args|
      expect(args[:model]).to eq(Search::AssistantQueryService::WRITING_MODEL)
      expect(args[:prompt]).to include("Requested draft type: email_draft")
      {
        text: {
          title: "Customer launch update draft",
          summary: "Created a launch update email draft for review.",
          payload: {
            to: [ "team@example.com" ],
            cc: [],
            subject: "Launch update",
            body: "Hi team,\n\nThe launch moved by two days. Please use the revised schedule.\n"
          },
          used_source_indices: [ 1 ]
        }.to_json,
        usage: { prompt_tokens: 88, completion_tokens: 44, total_tokens: 132 }
      }
    end

    sign_in user
    expect {
      post workspace_ai_assistant_path(workspace_slug: workspace.slug),
           params: {
             ai_assistant: {
               prompt: "Draft an email to team@example.com about the two day launch delay.",
               scope: Search::AssistantQueryService::SCOPE_WORKSPACE
             }
           },
           headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }
    }.to change(AgentAction, :count).by(1).and change(AiConversation, :count).by(1)

    agent_action = AgentAction.order(:created_at).last
    expect(agent_action.proposed_by).to eq("ai_assistant")
    expect(agent_action.draft_type).to eq("email_draft")
    expect(agent_action.payload_json.fetch("subject")).to eq("Launch update")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Review draft action")
    expect(response.body).to include("Created a launch update email draft for review.")

    conversation = AiConversation.order(:created_at).last
    expect(conversation.status).to eq(AiConversation::STATUS_SUGGESTION)
    expect(conversation.sources.map { |source| source["kind"] }).to include("Draft action")
  end

  it "creates native Nota drafts from AI prompts that ask for a note" do
    user = User.create!(email: "ai-assistant-nota-draft@example.com", password: "password123", openai_api_key: "sk-test")
    workspace = Workspace.create!(name: "AI Assistant Nota Draft", slug: "ai-assistant-nota-draft")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    page = Page.create!(workspace: workspace, created_by: user, title: "Meeting brief")
    SearchChunk.create!(
      workspace: workspace,
      source_type: SearchChunk::SOURCE_PAGE,
      source_id: page.id,
      page: page,
      chunk_index: 0,
      text: "The team agreed to prepare a decision brief and capture next steps in a dedicated note.",
      token_count: 15,
      content_hash: "assistant-nota-draft-hash",
      embedding: [ 0.2, 0.5 ],
      embedding_model: SearchChunk::EMBEDDING_MODEL
    )

    expect(Openai::ResponsesClient).to receive(:generate_text_with_usage) do |args|
      expect(args[:prompt]).to include("Requested draft type: nota_draft")
      {
        text: {
          title: "Decision brief draft",
          summary: "Created a Nota draft for review.",
          payload: {
            title: "Decision brief",
            body: "Summarize the decision, rationale, and next steps."
          },
          used_source_indices: [ 1 ]
        }.to_json,
        usage: { prompt_tokens: 70, completion_tokens: 40, total_tokens: 110 }
      }
    end

    sign_in user
    expect {
      post workspace_ai_assistant_path(workspace_slug: workspace.slug),
           params: {
             ai_assistant: {
               prompt: "Create a Nota with a decision brief from this page.",
               scope: Search::AssistantQueryService::SCOPE_WORKSPACE
             }
           },
           headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }
    }.to change(AgentAction, :count).by(1)

    agent_action = AgentAction.order(:created_at).last
    expect(agent_action.draft_type).to eq("nota_draft")
    expect(agent_action.target_system).to eq("notae")
    expect(agent_action.payload_json.fetch("title")).to eq("Decision brief")
    expect(response.body).to include("Created a Nota draft for review.")
  end

  it "falls back to general-knowledge answers when workspace context is not required" do
    user = User.create!(email: "ai-assistant-general-knowledge@example.com", password: "password123", openai_api_key: "sk-test")
    workspace = Workspace.create!(name: "AI Assistant General Knowledge", slug: "ai-assistant-general-knowledge")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    expect(Openai::ResponsesClient).to receive(:generate_text_with_usage) do |args|
      expect(args[:model]).to eq(Search::AssistantQueryService::GENERAL_MODEL)
      {
        text: "An alternative word for nice is pleasant.",
        usage: { prompt_tokens: 50, completion_tokens: 14, total_tokens: 64 }
      }
    end

    sign_in user
    post workspace_ai_assistant_path(workspace_slug: workspace.slug),
         params: { ai_assistant: { prompt: "What is an alternative word to nice?", scope: Search::AssistantQueryService::SCOPE_WORKSPACE } },
         headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("alternative word for nice is pleasant")
    expect(response.body).not_to include("could not find enough context")
    expect(AiConversation.order(:created_at).last.status).to eq(AiConversation::STATUS_SUCCESS)
  end

  it "uses web-backed answers for live questions and renders safe external sources" do
    user = User.create!(email: "ai-assistant-weather@example.com", password: "password123", openai_api_key: "sk-test", time_zone: "Australia/Melbourne")
    workspace = Workspace.create!(name: "AI Assistant Weather", slug: "ai-assistant-weather")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    page = Page.create!(workspace: workspace, created_by: user, title: "Weather page")

    expect(Openai::ResponsesClient).to receive(:generate_text_with_usage) do |args|
      expect(args[:tools]).to eq([ { type: Search::AssistantQueryService::WEB_SEARCH_TOOL_TYPE, user_location: { type: "approximate", timezone: "Australia/Melbourne" } } ])
      {
        text: "I need your location to answer today's weather.",
        usage: { prompt_tokens: 52, completion_tokens: 14, total_tokens: 66 },
        sources: [
          { title: "Trusted weather", url: "https://weather.example/today" }
        ]
      }
    end

    sign_in user
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))

    post workspace_ai_assistant_path(workspace_slug: workspace.slug),
         params: {
           ai_assistant: {
             prompt: "What is the weather today going to be?",
             scope: Search::AssistantQueryService::SCOPE_AUTO,
             current_page_id: page.id
           }
         },
         headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("I need your location to answer today&#39;s weather.")
    expect(response.body).to include("Trusted weather")
    expect(response.body).to include("https://weather.example/today")
    expect(response.body).to include("target=\"_blank\"")
    expect(response.body).to include("Live web")
    expect(response.body).to include("<details class=\"notae-ai-sources-panel\">")
    expect(response.body).not_to include("<details class=\"notae-ai-sources-panel\" open>")
    conversation = AiConversation.order(:created_at).last
    expect(conversation.answer).to eq("I need your location to answer today's weather.")
    expect(conversation.sources.first.fetch("url")).to eq("https://weather.example/today")
    expect(conversation).to be_live_web
  end

  it "restricts document scope to the current workspace page" do
    user = User.create!(email: "ai-assistant-document-scope@example.com", password: "password123", openai_api_key: "sk-test")
    workspace = Workspace.create!(name: "AI Assistant Scope", slug: "ai-assistant-scope")
    other_workspace = Workspace.create!(name: "AI Assistant Scope Other", slug: "ai-assistant-scope-other")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    Membership.create!(workspace: other_workspace, user: user, role: :owner)

    local_page = Page.create!(workspace: workspace, created_by: user, title: "Local Doc")
    local_page.blocks.create!(
      workspace: workspace,
      created_by: user,
      block_type: "paragraph",
      content_json: {
        "type" => "doc",
        "content" => [
          { "type" => "paragraph", "content" => [ { "type" => "text", "text" => "Local workspace details only." } ] }
        ]
      }
    )

    external_page = Page.create!(workspace: other_workspace, created_by: user, title: "External Doc")
    external_page.blocks.create!(
      workspace: other_workspace,
      created_by: user,
      block_type: "paragraph",
      content_json: {
        "type" => "doc",
        "content" => [
          { "type" => "paragraph", "content" => [ { "type" => "text", "text" => "Confidential external workspace text." } ] }
        ]
      }
    )

    captured_prompts = []
    allow(Openai::ResponsesClient).to receive(:generate_text_with_usage) do |args|
      captured_prompts << args[:prompt].to_s
      {
        text: "Answer from local doc [1].",
        usage: { prompt_tokens: 66, completion_tokens: 20, total_tokens: 86 }
      }
    end

    sign_in user
    post workspace_ai_assistant_path(workspace_slug: workspace.slug),
         params: {
           ai_assistant: {
             prompt: "Summarize this document",
             scope: Search::AssistantQueryService::SCOPE_DOCUMENT,
             current_page_id: external_page.id
           }
         },
         headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("could not find enough context")
    conversation = AiConversation.order(:created_at).last
    expect(conversation.status).to eq(AiConversation::STATUS_NOTICE)
    expect(captured_prompts).to be_empty

    post workspace_ai_assistant_path(workspace_slug: workspace.slug),
         params: {
           ai_assistant: {
             prompt: "Summarize this document",
             scope: Search::AssistantQueryService::SCOPE_DOCUMENT,
             current_page_id: local_page.id
           }
         },
         headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Answer from local doc")
    expect(captured_prompts.length).to eq(1)
    expect(captured_prompts.first).to include("Title=Local Doc")
    expect(captured_prompts.first).not_to include("Title=External Doc")
  end

  it "caps AI rail conversation rendering to the latest entries for page responsiveness" do
    user = User.create!(email: "ai-assistant-rail-cap@example.com", password: "password123")
    workspace = Workspace.create!(name: "AI Assistant Rail Cap", slug: "ai-assistant-rail-cap")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    limit = ApplicationController::AI_RAIL_CONVERSATION_LIMIT
    total = limit + 5
    total.times do |index|
      AiConversation.create!(
        user: user,
        workspace: workspace,
        prompt: "rail-cap-prompt-#{index}",
        answer: "rail-cap-answer-#{index}",
        scope: Search::AssistantQueryService::SCOPE_WORKSPACE,
        status: AiConversation::STATUS_SUCCESS,
        created_at: (total - index).minutes.ago
      )
    end

    sign_in user
    get workspace_ai_assistant_panel_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML.parse(response.body)
    prompt_nodes = document.css(".notae-ai-message.is-user .notae-ai-message-body")
    rendered_prompts = prompt_nodes.map(&:text)

    expect(rendered_prompts.count).to eq(limit)
    expect(rendered_prompts).to include("rail-cap-prompt-#{total - 1}")
    expect(rendered_prompts).not_to include("rail-cap-prompt-0")
  end

  it "renders internal links and only safe external source links in AI conversation history" do
    user = User.create!(email: "ai-assistant-source-links@example.com", password: "password123")
    workspace = Workspace.create!(name: "AI Assistant Source Links", slug: "ai-assistant-source-links")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    AiConversation.create!(
      user: user,
      workspace: workspace,
      prompt: "Source security check",
      answer: "Answer with source links",
      scope: Search::AssistantQueryService::SCOPE_WORKSPACE,
      status: AiConversation::STATUS_SUCCESS,
      sources: [
        { index: 1, title: "Internal page", kind: "Page", url: "/w/#{workspace.slug}" },
        { index: 2, title: "Trusted external", kind: "Web source", url: "https://weather.example/today" },
        { index: 3, title: "Scheme-relative", kind: "Page", url: "//malicious.example/steal" },
        { index: 4, title: "Javascript", kind: "Page", url: "javascript:alert(1)" }
      ]
    )

    sign_in user
    get workspace_ai_assistant_panel_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Internal page")
    expect(response.body).to include("Trusted external")
    expect(response.body).to include("weather.example/today")
    expect(response.body).not_to include("malicious.example")
    expect(response.body).not_to include("javascript:alert")
  end

  it "returns recent AI agent updates as rendered cards and respects the since cursor" do
    user = User.create!(email: "ai-assistant-updates@example.com", password: "password123")
    workspace = Workspace.create!(name: "AI Assistant Updates", slug: "ai-assistant-updates")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    stale_action = AgentAction.create!(
      workspace: workspace,
      user: user,
      proposed_by: "ai_assistant",
      target_system: "gmail",
      draft_type: "email_draft",
      title: "Stale email draft",
      payload_json: {
        "to" => [ "team@example.com" ],
        "cc" => [],
        "subject" => "Stale subject",
        "body" => "Older body copy."
      },
      status: AgentAction::STATUS_PENDING,
      approval_required: true,
      dry_run: true
    )
    stale_action.update_column(:updated_at, 2.hours.ago)

    WorkflowRun.create!(
      workspace: workspace,
      user: user,
      workflow_kind: WorkflowRun::KIND_CREATE_NOTA,
      status: WorkflowRun::STATUS_SUCCEEDED,
      trigger_source: "manual",
      queued_at: 8.minutes.ago,
      finished_at: 7.minutes.ago,
      confidence_score: 1.0,
      result_json: { "title" => "Ignored manual workflow" }
    )

    fresh_workflow_run = WorkflowRun.create!(
      workspace: workspace,
      user: user,
      workflow_kind: WorkflowRun::KIND_CREATE_TASK,
      status: WorkflowRun::STATUS_SUCCEEDED,
      trigger_source: "automation_agent",
      queued_at: 6.minutes.ago,
      finished_at: 5.minutes.ago,
      confidence_score: 1.0,
      result_json: { "title" => "Roadmap follow-up task" }
    )
    fresh_workflow_run.update_column(:updated_at, 5.minutes.ago)

    proactive_suggestion = KnowledgeSuggestion.create!(
      workspace: workspace,
      user: user,
      kind: KnowledgeSuggestion::KIND_PROACTIVE,
      status: KnowledgeSuggestion::STATUS_ACTIVE,
      title: "Escalate approval gap",
      summary: "The approval gap still needs attention. [1]",
      task_suggestions_json: [
        { "title" => "Follow up with approver", "owner" => "Errol", "rationale" => "The approval is blocking rollout. [1]" }
      ],
      sources_json: [ { "index" => 1, "title" => "Launch note", "url" => "/w/#{workspace.slug}/pages/test" } ],
      generated_at: 4.minutes.ago,
      expires_at: 6.hours.from_now
    )
    proactive_suggestion.update_column(:updated_at, 4.minutes.ago)

    sign_in user
    get workspace_ai_assistant_updates_path(workspace_slug: workspace.slug),
        params: { since: 30.minutes.ago.iso8601 },
        headers: { "ACCEPT" => "application/json" }

    expect(response).to have_http_status(:ok)

    payload = JSON.parse(response.body)
    expect(payload.dig("data", "count")).to eq(2)
    expect(payload.dig("data", "latest_at")).to eq(proactive_suggestion.reload.updated_at.iso8601)

    html = payload.dig("data", "html")
    expect(html).to include("Update available from Agent")
    expect(html).to include("Roadmap follow-up task")
    expect(html).to include("Workflow: Create task")
    expect(html).to include("Escalate approval gap")
    expect(html).to include("Suggestion: Suggested next step")
    expect(html).to include(workspace_path(workspace.slug, show_home: 1, anchor: "knowledge-suggestion-#{proactive_suggestion.id}"))
    expect(html).to include("Open full window")
    expect(html).to include(workflow_run_path(workspace_slug: workspace.slug, id: fresh_workflow_run.id))
    expect(html).not_to include("Stale email draft")
    expect(html).not_to include("Ignored manual workflow")
  end
end
