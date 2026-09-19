require "rails_helper"

RSpec.describe Search::AssistantAgentService do
  let(:user) do
    User.create!(
      email: "assistant-agent@example.com",
      password: "password123",
      openai_api_key: "sk-test",
      time_zone: "Australia/Melbourne"
    )
  end
  let(:workspace) { Workspace.create!(name: "Assistant Agent", slug: "assistant-agent") }

  before do
    Membership.create!(workspace: workspace, user: user, role: :owner)
    allow(Search::AiBudgetGuard).to receive(:within_daily_budget?).and_return(true)
    allow(Search::AiRateLimiter).to receive(:allowed?).and_return(true)
  end

  it "runs a model-selected Notae tool and returns its output to the model before answering" do
    route = Search::AssistantModelRouter::Route.new(
      tier: "terra",
      model: "gpt-5.6-terra",
      reasoning_effort: "medium",
      usage: Openai::ResponsesClient.default_usage
    )
    router = instance_double(Search::AssistantModelRouter, call: route)
    allow(Search::AssistantModelRouter).to receive(:new).and_return(router)

    registry = instance_double(
      Search::AssistantToolRegistry,
      definitions: [ { type: "function", name: "update_nota" } ],
      sources: [
        {
          title: "Renamed document",
          kind: "Completed action",
          url: "/w/assistant-agent/pages/page-1",
          workspace_name: workspace.name
        }
      ],
      executed_tools: [ "update_nota" ]
    )
    allow(registry).to receive(:call).with(
      name: "update_nota",
      arguments: { "page_id" => "page-1", "title" => "Renamed document", "body" => "", "body_mode" => "keep" }
    ).and_return(ok: true, status: "succeeded")
    allow(Search::AssistantToolRegistry).to receive(:new).and_return(registry)

    first_response = {
      id: "resp_tool",
      text: "",
      function_calls: [
        {
          name: "update_nota",
          call_id: "call_1",
          arguments: { "page_id" => "page-1", "title" => "Renamed document", "body" => "", "body_mode" => "keep" }
        }
      ],
      usage: { prompt_tokens: 50, completion_tokens: 12, total_tokens: 62 },
      sources: []
    }
    final_response = {
      id: "resp_final",
      text: "Renamed the document.",
      function_calls: [],
      usage: { prompt_tokens: 20, completion_tokens: 8, total_tokens: 28 },
      sources: []
    }
    allow(Openai::ResponsesClient).to receive(:create).and_return(first_response, final_response)

    response = described_class.new(
      user: user,
      workspace: workspace,
      prompt: "Give this document the clearer title Renamed document.",
      scope: Search::AssistantQueryService::SCOPE_AUTO
    ).call

    expect(response.answer).to eq("Renamed the document.")
    expect(response.model).to eq("gpt-5.6-terra")
    expect(response.sources.first).to include(kind: "Completed action", index: 1)
    expect(Openai::ResponsesClient).to have_received(:create).twice
    expect(Openai::ResponsesClient).to have_received(:create).with(
      hash_including(
        previous_response_id: "resp_tool",
        prompt_cache_key: match(/\Anotae-assistant-v1-[a-f0-9]{24}\z/),
        prompt_cache_options: { ttl: "30m" },
        input: [
          hash_including(
            type: "function_call_output",
            call_id: "call_1",
            output: include('"ok":true')
          )
        ]
      )
    )
  end

  it "uses hosted web search for any current outside request and preserves clickable sources" do
    route = Search::AssistantModelRouter::Route.new(
      tier: "luna",
      model: "gpt-5.6-luna",
      reasoning_effort: "none",
      usage: Openai::ResponsesClient.default_usage
    )
    allow_any_instance_of(Search::AssistantModelRouter).to receive(:call).and_return(route)
    registry = instance_double(Search::AssistantToolRegistry, definitions: [], sources: [], executed_tools: [])
    allow(Search::AssistantToolRegistry).to receive(:new).and_return(registry)
    allow(Openai::ResponsesClient).to receive(:create).and_return(
      id: "resp_web",
      text: "Here is the seven-day forecast.",
      function_calls: [],
      usage: { prompt_tokens: 40, completion_tokens: 20, total_tokens: 60 },
      sources: [ { title: "Bureau of Meteorology", url: "https://weather.example/forecast" } ]
    )

    response = described_class.new(
      user: user,
      workspace: workspace,
      prompt: "Could you check outside Notae and give me the next seven days of weather?",
      scope: Search::AssistantQueryService::SCOPE_AUTO
    ).call

    expect(response.sources).to eq(
      [
        {
          title: "Bureau of Meteorology",
          kind: "Web source",
          url: "https://weather.example/forecast",
          index: 1
        }
      ]
    )
    expect(Openai::ResponsesClient).to have_received(:create).with(
      hash_including(
        tools: include(hash_including(type: "web_search")),
        include: [ "web_search_call.action.sources" ]
      )
    )
  end

  it "does not call a model when document scope has no authorized current document" do
    allow(Openai::ResponsesClient).to receive(:create)

    service = described_class.new(
      user: user,
      workspace: workspace,
      prompt: "Summarise this document",
      scope: Search::AssistantQueryService::SCOPE_DOCUMENT
    )

    expect(service.call).to be_nil
    expect(service.unavailable_reason).to eq(:no_context)
    expect(Openai::ResponsesClient).not_to have_received(:create)
  end
end
