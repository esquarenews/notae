require "rails_helper"

RSpec.describe Search::AssistantModelRouter do
  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("OPENAI_ASSISTANT_ROUTER_MODEL").and_return(nil)
    allow(ENV).to receive(:[]).with("OPENAI_ASSISTANT_MODEL_LUNA").and_return(nil)
    allow(ENV).to receive(:[]).with("OPENAI_ASSISTANT_MODEL_TERRA").and_return(nil)
    allow(ENV).to receive(:[]).with("OPENAI_ASSISTANT_MODEL_SOL").and_return(nil)
  end

  it "uses a model-generated JSON decision and carries routing usage" do
    allow(Openai::ResponsesClient).to receive(:create).and_return(
      text: JSON.generate(tier: "sol", reasoning_effort: "xhigh"),
      usage: { prompt_tokens: 80, completion_tokens: 12, total_tokens: 92 }
    )
    router = described_class.new(api_key: "sk-test", safety_identifier: "user_hash")

    route = router.call(
      request: "Handle this request based on its full requirements.",
      context: { scope: "workspace", available_tools: %w[search create_nota] }
    )

    expect(route.to_h).to eq(
      tier: "sol",
      model: "gpt-5.6-sol",
      reasoning_effort: "xhigh",
      usage: { prompt_tokens: 80, completion_tokens: 12, total_tokens: 92 }
    )
    expect(Openai::ResponsesClient).to have_received(:create) do |arguments|
      input = JSON.parse(arguments.fetch(:input))
      expect(input).to eq(
        "request" => "Handle this request based on its full requirements.",
        "context" => { "scope" => "workspace", "available_tools" => %w[search create_nota] }
      )
      expect(arguments).to include(
        api_key: "sk-test",
        model: "gpt-5.6-luna",
        reasoning: { effort: "none" },
        text: { format: described_class::ROUTE_SCHEMA },
        safety_identifier: "user_hash",
        max_output_tokens: 120
      )
      expect(arguments.fetch(:instructions)).to include("complete request and supplied context semantically")
    end
  end

  it "honors configurable router and tier models" do
    allow(ENV).to receive(:[]).with("OPENAI_ASSISTANT_ROUTER_MODEL").and_return("router-model")
    allow(ENV).to receive(:[]).with("OPENAI_ASSISTANT_MODEL_LUNA").and_return("luna-model")
    allow(ENV).to receive(:[]).with("OPENAI_ASSISTANT_MODEL_TERRA").and_return("terra-model")
    allow(ENV).to receive(:[]).with("OPENAI_ASSISTANT_MODEL_SOL").and_return("sol-model")
    allow(Openai::ResponsesClient).to receive(:create).and_return(
      text: JSON.generate(tier: "luna", reasoning_effort: "low"),
      usage: Openai::ResponsesClient.default_usage
    )

    route = described_class.new(api_key: "sk-test").call(request: "A request")

    expect(route.model).to eq("luna-model")
    expect(described_class.model_for("terra")).to eq("terra-model")
    expect(described_class.model_for("sol")).to eq("sol-model")
    expect(Openai::ResponsesClient).to have_received(:create).with(hash_including(model: "router-model"))
  end

  it "follows the semantic route response rather than matching prompt keywords" do
    allow(Openai::ResponsesClient).to receive(:create).and_return(
      text: JSON.generate(tier: "terra", reasoning_effort: "medium"),
      usage: Openai::ResponsesClient.default_usage
    )

    route = described_class.new(api_key: "sk-test").call(
      request: "Weather football title calendar summary",
      context: { task_shape: "supplied by the orchestrator" }
    )

    expect(route.tier).to eq("terra")
    expect(route.model).to eq("gpt-5.6-terra")
  end

  it "falls back to the balanced tier for invalid JSON or provider errors" do
    allow(Openai::ResponsesClient).to receive(:create).and_return(text: "not-json", usage: {})
    router = described_class.new(api_key: "sk-test")

    invalid_route = router.call(request: "First request")
    allow(Openai::ResponsesClient).to receive(:create).and_raise(Openai::ResponsesClient::Error, "unavailable")
    provider_route = router.call(request: "Second request")

    [ invalid_route, provider_route ].each do |route|
      expect(route.to_h).to eq(
        tier: "terra",
        model: "gpt-5.6-terra",
        reasoning_effort: "medium",
        usage: { prompt_tokens: 0, completion_tokens: 0, total_tokens: 0 }
      )
    end
  end

  it "does not spend a routing request on blank input" do
    allow(Openai::ResponsesClient).to receive(:create)

    route = described_class.new(api_key: "sk-test").call(request: "  ")

    expect(route.tier).to eq("terra")
    expect(Openai::ResponsesClient).not_to have_received(:create)
  end
end
