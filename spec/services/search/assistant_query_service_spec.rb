require "rails_helper"

RSpec.describe Search::AssistantQueryService do
  it "returns a cited answer for workspace scope questions" do
    user = User.create!(email: "assistant-workspace@example.com", password: "password123", openai_api_key: "sk-test")
    workspace = Workspace.create!(name: "Assistant Workspace", slug: "assistant-workspace")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    page = Page.create!(workspace: workspace, created_by: user, title: "Mac Notes")
    SearchChunk.create!(
      workspace: workspace,
      source_type: SearchChunk::SOURCE_PAGE,
      source_id: page.id,
      page: page,
      chunk_index: 0,
      text: "Mac is mentioned in the release checklist",
      token_count: 8,
      content_hash: "assistant-chunk-1",
      embedding: [ 1.0, 0.0 ],
      embedding_model: SearchChunk::EMBEDDING_MODEL
    )

    allow(Openai::ResponsesClient).to receive(:generate_text_with_usage).and_return(
      {
        text: "Yes, Mac is mentioned [1].",
        usage: { prompt_tokens: 90, completion_tokens: 20, total_tokens: 110 }
      }
    )

    response = described_class.new(
      user: user,
      workspace: workspace,
      prompt: "Is Mac mentioned in this workspace?",
      scope: Search::AssistantQueryService::SCOPE_WORKSPACE
    ).call

    expect(response).to be_present
    expect(response.answer).to include("[1]")
    expect(response.sources.length).to eq(1)
    expect(response.sources.first[:title]).to eq("Mac Notes")
    usage = AiUsageLog.where(user: user, workspace: workspace, operation: AiUsageLog::OP_ASSISTANT_QUERY)
    expect(usage).to exist
  end

  it "returns no-context when document scope is requested without a page" do
    user = User.create!(email: "assistant-doc-empty@example.com", password: "password123", openai_api_key: "sk-test")
    workspace = Workspace.create!(name: "Assistant Doc Empty", slug: "assistant-doc-empty")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    service = described_class.new(
      user: user,
      workspace: workspace,
      prompt: "Summarize this document",
      scope: Search::AssistantQueryService::SCOPE_DOCUMENT
    )
    response = service.call

    expect(response).to be_nil
    expect(service.unavailable_reason).to eq(:no_context)
  end

  it "drops invalid citations and keeps mapped sources only" do
    user = User.create!(email: "assistant-citation@example.com", password: "password123", openai_api_key: "sk-test")
    workspace = Workspace.create!(name: "Assistant Citation", slug: "assistant-citation")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    page = Page.create!(workspace: workspace, created_by: user, title: "Summary Source")
    SearchChunk.create!(
      workspace: workspace,
      source_type: SearchChunk::SOURCE_PAGE,
      source_id: page.id,
      page: page,
      chunk_index: 0,
      text: "First chunk text",
      token_count: 3,
      content_hash: "assistant-chunk-2",
      embedding: [ 0.2, 0.4 ],
      embedding_model: SearchChunk::EMBEDDING_MODEL
    )

    allow(Openai::ResponsesClient).to receive(:generate_text_with_usage).and_return(
      {
        text: "Summary [99] valid part [1].",
        usage: { prompt_tokens: 90, completion_tokens: 20, total_tokens: 110 }
      }
    )

    response = described_class.new(
      user: user,
      workspace: workspace,
      prompt: "Summarize",
      scope: Search::AssistantQueryService::SCOPE_WORKSPACE
    ).call

    expect(response).to be_present
    expect(response.answer).not_to include("[99]")
    expect(response.sources.map { |source| source[:index] }).to eq([ 1 ])
  end

  it "supports whole-account scope across accessible workspaces" do
    user = User.create!(email: "assistant-account@example.com", password: "password123", openai_api_key: "sk-test")
    primary_workspace = Workspace.create!(name: "Assistant Account Primary", slug: "assistant-account-primary")
    secondary_workspace = Workspace.create!(name: "Assistant Account Secondary", slug: "assistant-account-secondary")
    Membership.create!(workspace: primary_workspace, user: user, role: :owner)
    Membership.create!(workspace: secondary_workspace, user: user, role: :owner)
    page = Page.create!(workspace: secondary_workspace, created_by: user, title: "Cross-workspace doc")
    SearchChunk.create!(
      workspace: secondary_workspace,
      source_type: SearchChunk::SOURCE_PAGE,
      source_id: page.id,
      page: page,
      chunk_index: 0,
      text: "Account-wide mention for billing and launch details",
      token_count: 7,
      content_hash: "assistant-account-chunk",
      embedding: [ 0.3, 0.7 ],
      embedding_model: SearchChunk::EMBEDDING_MODEL
    )

    allow(Openai::ResponsesClient).to receive(:generate_text_with_usage).and_return(
      {
        text: "Found in another workspace [1].",
        usage: { prompt_tokens: 90, completion_tokens: 20, total_tokens: 110 }
      }
    )

    response = described_class.new(
      user: user,
      workspace: primary_workspace,
      prompt: "Where is billing mentioned across my account?",
      scope: Search::AssistantQueryService::SCOPE_ACCOUNT
    ).call

    expect(response).to be_present
    expect(response.answer).to include("[1]")
    expect(response.sources.first[:workspace_name]).to eq("Assistant Account Secondary")
  end
end
