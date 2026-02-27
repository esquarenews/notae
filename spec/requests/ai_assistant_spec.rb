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
    expect(response.body).to include("ai_rail_panel")
    expect(response.body).to include("ai_conversation_history_list")
    expect(response.body).to include("notae-ai-thread")
    expect(response.body).to include("Is Mac mentioned?")
    expect(response.body).to include("Copy result")
    expect(response.body).to include("Yes, Mac is mentioned")

    conversation = AiConversation.order(:created_at).last
    expect(conversation.prompt).to eq("Is Mac mentioned?")
    expect(conversation.answer).to include("Yes, Mac is mentioned")
    expect(conversation.status).to eq(AiConversation::STATUS_SUCCESS)
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
end
