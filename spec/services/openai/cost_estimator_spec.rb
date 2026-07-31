require "rails_helper"

RSpec.describe Openai::CostEstimator do
  it "configures current standard GPT-5.6 prices per 1,000 tokens" do
    pricing = Rails.application.config.x.ai_pricing

    expect(pricing.gpt_5_6_sol_input_per_1k).to eq(0.005)
    expect(pricing.gpt_5_6_sol_output_per_1k).to eq(0.03)
    expect(pricing.gpt_5_6_terra_input_per_1k).to eq(0.002)
    expect(pricing.gpt_5_6_terra_cached_input_per_1k).to eq(0.0002)
    expect(pricing.gpt_5_6_terra_output_per_1k).to eq(0.012)
    expect(pricing.gpt_5_6_luna_input_per_1k).to eq(0.0002)
    expect(pricing.gpt_5_6_luna_cached_input_per_1k).to eq(0.00002)
    expect(pricing.gpt_5_6_luna_output_per_1k).to eq(0.0012)
  end

  it "estimates each GPT-5.6 tier using its configured standard rates" do
    expect(described_class.estimate(model: "gpt-5.6-sol", prompt_tokens: 1_000, completion_tokens: 1_000)).to eq(0.035)
    expect(described_class.estimate(model: "gpt-5.6", prompt_tokens: 1_000, completion_tokens: 1_000)).to eq(0.035)
    expect(described_class.estimate(model: "gpt-5.6-terra", prompt_tokens: 1_000, completion_tokens: 1_000)).to eq(0.014)
    expect(described_class.estimate(model: "gpt-5.6-luna", prompt_tokens: 1_000, completion_tokens: 1_000)).to eq(0.0014)
  end

  it "uses environment-backed application configuration for GPT-5.6 estimates" do
    pricing = Rails.application.config.x.ai_pricing
    allow(pricing).to receive(:gpt_5_6_terra_input_per_1k).and_return(0.009)
    allow(pricing).to receive(:gpt_5_6_terra_output_per_1k).and_return(0.021)

    cost = described_class.estimate(
      model: "gpt-5.6-terra",
      prompt_tokens: 2_000,
      completion_tokens: 1_000
    )

    expect(cost).to eq(0.039)
  end

  it "prices cache reads, cache writes, Flex processing, and web searches separately" do
    cost = described_class.estimate(
      model: "gpt-5.6-terra",
      prompt_tokens: 4_000,
      cached_prompt_tokens: 1_000,
      cache_write_tokens: 1_000,
      completion_tokens: 1_000,
      web_search_calls: 2,
      service_tier: "flex"
    )

    expect(cost).to eq(0.02935)
  end

  it "falls back to per-minute transcription pricing when token usage is unavailable" do
    expect(
      described_class.estimate(
        model: "gpt-4o-transcribe-diarize",
        prompt_tokens: 0,
        completion_tokens: 0,
        audio_minutes: 10
      )
    ).to eq(0.06)
  end

  it "uses transcription token pricing when the API returns usage" do
    expect(
      described_class.estimate(
        model: "gpt-4o-mini-transcribe",
        prompt_tokens: 1_000,
        completion_tokens: 500,
        audio_minutes: 10
      )
    ).to eq(0.00375)
  end

  it "applies GPT-5.6 long-context rates above 272,000 input tokens" do
    expect(
      described_class.estimate(
        model: "gpt-5.6-terra",
        prompt_tokens: 273_000,
        completion_tokens: 1_000
      )
    ).to eq(1.11)
  end

  it "estimates gpt-4.1 usage with configured pricing rates" do
    allow(Rails.application.config.x.ai_pricing).to receive(:gpt_4_1_input_per_1k).and_return(0.002)
    allow(Rails.application.config.x.ai_pricing).to receive(:gpt_4_1_output_per_1k).and_return(0.008)

    cost = described_class.estimate(
      model: "gpt-4.1",
      prompt_tokens: 1_500,
      completion_tokens: 500
    )

    expect(cost).to eq(0.007)
  end

  it "retains pricing support for existing models and treats unknown models as free" do
    pricing = Rails.application.config.x.ai_pricing

    expect(described_class.estimate(model: "text-embedding-3-small", prompt_tokens: 1_000, completion_tokens: 500))
      .to eq(pricing.embedding_3_small_input_per_1k)
    expect(described_class.estimate(model: "gpt-4o-mini", prompt_tokens: 1_000, completion_tokens: 1_000))
      .to eq((pricing.gpt_4o_mini_input_per_1k + pricing.gpt_4o_mini_output_per_1k).round(6))
    expect(described_class.estimate(model: "gpt-4.1-mini", prompt_tokens: 1_000, completion_tokens: 1_000))
      .to eq((pricing.gpt_4_1_mini_input_per_1k + pricing.gpt_4_1_mini_output_per_1k).round(6))
    expect(described_class.estimate(model: "custom-model", prompt_tokens: 1_000, completion_tokens: 1_000)).to eq(0.0)
  end
end
