require "rails_helper"
require "ostruct"

RSpec.describe Meetings::SummaryAndActionsService do
  def build_session(transcript:)
    user = OpenStruct.new(
      openai_api_key: "sk-test",
      openai_api_key_configured?: true
    )
    workspace = OpenStruct.new(id: "workspace-1")
    OpenStruct.new(
      id: "session-1",
      transcript_text: transcript,
      created_by: user,
      workspace: workspace
    )
  end

  it "uses balanced GPT-5.6 reasoning and filters weak or non-actionable tasks" do
    session = build_session(transcript: "Alex will send the proposal. Team discussed roadmap ideas.")
    response_payload = {
      summary_bullets: [ "Reviewed proposal scope." ],
      decisions: [ "Ship in two phases." ],
      action_items: [
        { title: "Send updated proposal to client", owner: "Alex", due_at: "2026-03-05 10:00", confidence: 0.88 },
        { title: "Discuss roadmap options", owner: "Team", due_at: "", confidence: 0.92 },
        { title: "prepare release checklist", owner: "Sam", due_at: "", confidence: 0.51 },
        { title: "Send updated proposal to client", owner: "Alex", due_at: "", confidence: 0.90 }
      ]
    }.to_json

    allow(Openai::ResponsesClient).to receive(:generate_text_with_usage)
      .and_return({ text: response_payload, usage: { prompt_tokens: 120, completion_tokens: 80, total_tokens: 200 } })
    allow(Search::AiUsageLogger).to receive(:log!)

    result = described_class.new(session: session).call

    expect(Openai::ResponsesClient).to have_received(:generate_text_with_usage).with(
      hash_including(
        model: "gpt-5.6-terra",
        reasoning: { effort: "medium" },
        prompt_cache_key: "notae-meeting-summary-v1",
        prompt_cache_options: { ttl: "30m" }
      )
    )
    expect(result[:summary_markdown]).to include("### Summary")
    expect(result[:action_items].size).to eq(1)
    expect(result[:action_items].first["title"]).to eq("Send updated proposal to client")
    expect(result[:action_items].first["owner"]).to eq("Alex")
    expect(result[:action_items].first["due_at"]).to end_with("Z")
    expect(result[:action_items].first["confidence"]).to eq(0.88)
    expect(Search::AiUsageLogger).to have_received(:log!).with(
      hash_including(operation: AiUsageLog::OP_MEETING_SUMMARY)
    )
  end

  it "falls back when no OpenAI key is configured" do
    session = OpenStruct.new(
      transcript_text: "One. Two. Three.",
      created_by: OpenStruct.new(openai_api_key_configured?: false),
      workspace: OpenStruct.new(id: "workspace-1"),
      id: "session-2"
    )

    result = described_class.new(session: session).call
    expect(result[:summary_markdown]).to include("- One.")
    expect(result[:action_items]).to eq([])
  end
end
