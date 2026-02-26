require "rails_helper"

RSpec.describe "AI Assistant", type: :request do
  it "returns a turbo-stream sidebar update with answer and copy action" do
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
    post workspace_ai_assistant_path(workspace_slug: workspace.slug),
         params: { ai_assistant: { prompt: "Is Mac mentioned?", scope: "this-will-fallback", current_page_id: page.id } },
         headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("turbo-stream")
    expect(response.body).to include("ai_rail_panel")
    expect(response.body).to include("Copy result")
    expect(response.body).to include("Yes, Mac is mentioned")
  end

  it "shows a no-context notice for document scope without current document" do
    user = User.create!(email: "ai-assistant-no-context@example.com", password: "password123", openai_api_key: "sk-test")
    workspace = Workspace.create!(name: "AI Assistant No Context", slug: "ai-assistant-no-context")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    sign_in user
    post workspace_ai_assistant_path(workspace_slug: workspace.slug),
         params: { ai_assistant: { prompt: "Summarise this document", scope: Search::AssistantQueryService::SCOPE_DOCUMENT } },
         headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("could not find enough context")
  end
end
