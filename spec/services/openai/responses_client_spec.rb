require "rails_helper"

RSpec.describe Openai::ResponsesClient do
  it "passes optional tools/include payload and extracts web sources" do
    allow(described_class).to receive(:request_response!).and_return(
      {
        "output_text" => "It will be mild today.",
        "usage" => { "input_tokens" => 21, "output_tokens" => 7, "total_tokens" => 28 },
        "output" => [
          {
            "type" => "web_search_call",
            "action" => {
              "sources" => [
                { "title" => "Weather", "url" => "https://weather.example/today" }
              ]
            }
          }
        ]
      }
    )

    response = described_class.generate_text_with_usage(
      prompt: "What is the weather today?",
      api_key: "sk-test",
      model: "gpt-4.1-mini",
      max_output_tokens: 300,
      tools: [ { type: "web_search" } ],
      include: [ "web_search_call.action.sources" ]
    )

    expect(described_class).to have_received(:request_response!).with(
      hash_including(
        tools: [ { type: "web_search" } ],
        include: [ "web_search_call.action.sources" ]
      )
    )
    expect(response[:text]).to eq("It will be mild today.")
    expect(response[:sources]).to eq([ { title: "Weather", url: "https://weather.example/today" } ])
  end
end
