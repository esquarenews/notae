require "rails_helper"

RSpec.describe "API V1 Knowledge", type: :request do
  include ActiveJob::TestHelper

  def json_body
    JSON.parse(response.body)
  end

  def auth_headers(token)
    { "Authorization" => "Bearer #{token.token}", "Accept" => "application/json" }
  end

  it "enqueues workspace knowledge ingestion" do
    user = User.create!(email: "api-knowledge-ingest@example.com", password: "password123")
    workspace = Workspace.create!(name: "API knowledge ingest", slug: "api-knowledge-ingest")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    token = ApiToken.create!(user: user, name: "Knowledge ingest API")

    ActiveJob::Base.queue_adapter = :test

    expect do
      post "/api/v1/workspaces/#{workspace.slug}/knowledge/ingestions",
           headers: auth_headers(token)
    end.to have_enqueued_job(Search::IngestWorkspaceKnowledgeJob).with(workspace.id, user.id)

    expect(response).to have_http_status(:accepted)
    expect(json_body.dig("data", "enqueued")).to eq(true)
  end

  it "returns cited knowledge suggestions with provenance-backed sources" do
    user = User.create!(email: "api-knowledge-suggest@example.com", password: "password123", openai_api_key: "sk-test")
    workspace = Workspace.create!(name: "API knowledge suggest", slug: "api-knowledge-suggest")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    token = ApiToken.create!(user: user, name: "Knowledge suggest API")

    page = Page.create!(workspace: workspace, created_by: user, title: "Brief")
    SearchChunk.create!(
      workspace: workspace,
      source_type: SearchChunk::SOURCE_PAGE,
      source_id: page.id,
      page: page,
      chunk_index: 0,
      text: "Alex will send the updated brief.",
      token_count: 6,
      content_hash: "chunk-api-1",
      source_content_hash: "source-api-1",
      source_uri: "/w/#{workspace.slug}/pages/#{page.id}",
      source_title: page.title,
      metadata_json: { "entities" => { "names" => [ "Alex" ] } }
    )

    allow(Openai::ResponsesClient).to receive(:generate_text_with_usage).and_return(
      {
        text: {
          summary: "The brief still needs to go out. [1]",
          insights: [ "Alex owns the next handoff. [1]" ],
          task_suggestions: [
            {
              title: "Confirm brief distribution",
              owner: "Alex",
              rationale: "The current note says Alex will send it. [1]",
              citation_indices: [ 1 ]
            }
          ],
          related_notes: [
            {
              title: "Brief",
              reason: "This note is the current source of truth. [1]",
              citation_indices: [ 1 ]
            }
          ]
        }.to_json,
        usage: { prompt_tokens: 21, completion_tokens: 17, total_tokens: 38 }
      }
    )

    get "/api/v1/workspaces/#{workspace.slug}/knowledge/suggestions", headers: auth_headers(token)

    expect(response).to have_http_status(:ok)
    expect(json_body.dig("data", "summary")).to include("[1]")
    expect(json_body.dig("data", "sources", 0, "source_content_hash")).to eq("source-api-1")
  end
end
