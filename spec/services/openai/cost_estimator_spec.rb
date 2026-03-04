require "rails_helper"

RSpec.describe Openai::CostEstimator do
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
end
