require "rails_helper"

RSpec.describe Openai::ResponsesClient do
  describe ".create" do
    it "sends the supported Responses API fields and returns normalized output" do
      response_body = {
        "id" => "resp_123",
        "usage" => { "input_tokens" => 31, "output_tokens" => 12, "total_tokens" => 43 },
        "output" => [
          {
            "type" => "function_call",
            "id" => "fc_123",
            "call_id" => "call_123",
            "name" => "create_nota",
            "arguments" => JSON.generate(title: "Launch notes", blocks: [ "First" ]),
            "status" => "completed"
          },
          {
            "type" => "message",
            "content" => [
              {
                "type" => "output_text",
                "text" => "I prepared the nota.",
                "annotations" => [
                  { "type" => "url_citation", "title" => "Reference", "url" => "https://example.com/reference" }
                ]
              }
            ]
          }
        ]
      }
      allow(described_class).to receive(:request_payload!).and_return(response_body)

      result = described_class.create(
        input: [ { role: "user", content: "Create the launch nota" } ],
        api_key: "  sk-test  ",
        model: "  gpt-5.6-terra  ",
        instructions: "Complete the request.",
        tools: [ { type: "function", name: "create_nota", parameters: { type: "object" } } ],
        include: [ "reasoning.encrypted_content" ],
        previous_response_id: "resp_previous",
        reasoning: { effort: "medium" },
        text: { verbosity: "low" },
        parallel_tool_calls: false,
        safety_identifier: "user_hash_123",
        service_tier: "flex",
        prompt_cache_key: "notae-test-cache",
        prompt_cache_options: { ttl: "30m" },
        max_output_tokens: 640
      )

      expect(described_class).to have_received(:request_payload!).with(
        api_key: "sk-test",
        payload: {
          model: "gpt-5.6-terra",
          input: [ { role: "user", content: "Create the launch nota" } ],
          instructions: "Complete the request.",
          tools: [ { type: "function", name: "create_nota", parameters: { type: "object" } } ],
          include: [ "reasoning.encrypted_content" ],
          previous_response_id: "resp_previous",
          reasoning: { effort: "medium" },
          text: { verbosity: "low" },
          parallel_tool_calls: false,
          safety_identifier: "user_hash_123",
          service_tier: "flex",
          prompt_cache_key: "notae-test-cache",
          prompt_cache_options: { ttl: "30m" },
          max_output_tokens: 640
        }
      )
      expect(result).to include(
        id: "resp_123",
        text: "I prepared the nota.",
        usage: { prompt_tokens: 31, completion_tokens: 12, total_tokens: 43 },
        sources: [ { title: "Reference", url: "https://example.com/reference" } ],
        raw: response_body
      )
      expect(result[:function_calls]).to eq(
        [
          {
            id: "fc_123",
            call_id: "call_123",
            name: "create_nota",
            arguments: { "title" => "Launch notes", "blocks" => [ "First" ] },
            raw_arguments: '{"title":"Launch notes","blocks":["First"]}',
            status: "completed"
          }
        ]
      )
    end

    it "includes empty arrays but omits optional nil and blank identifier fields" do
      allow(described_class).to receive(:request_payload!).and_return({ "output" => [] })

      described_class.create(
        input: "Hello",
        api_key: "sk-test",
        model: "gpt-5.6-luna",
        tools: [],
        include: [],
        safety_identifier: "",
        parallel_tool_calls: true
      )

      expect(described_class).to have_received(:request_payload!).with(
        api_key: "sk-test",
        payload: {
          model: "gpt-5.6-luna",
          input: "Hello",
          tools: [],
          include: [],
          parallel_tool_calls: true
        }
      )
    end

    it "rejects missing credentials and models before making a request" do
      allow(described_class).to receive(:request_payload!)

      expect do
        described_class.create(input: "Hello", api_key: " ", model: "gpt-5.6-luna")
      end.to raise_error(described_class::Error, "Missing OpenAI API key")
      expect do
        described_class.create(input: "Hello", api_key: "sk-test", model: " ")
      end.to raise_error(described_class::Error, "Missing OpenAI model")
      expect(described_class).not_to have_received(:request_payload!)
    end
  end

  describe ".generate_text_with_usage" do
    it "preserves the legacy optional tools/include request and extracts web sources" do
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

    it "returns an empty legacy response without calling the API for a blank prompt" do
      allow(described_class).to receive(:request_response!)

      expect(described_class.generate_text_with_usage(prompt: " ", api_key: nil)).to eq(
        text: "",
        usage: { prompt_tokens: 0, completion_tokens: 0, total_tokens: 0 },
        sources: []
      )
      expect(described_class).not_to have_received(:request_response!)
    end

    it "passes GPT-5.6 reasoning, service tier, and cache options and records cache and web usage" do
      allow(described_class).to receive(:request_response!).and_return(
        {
          "service_tier" => "flex",
          "usage" => {
            "input_tokens" => 2_000,
            "output_tokens" => 100,
            "total_tokens" => 2_100,
            "input_tokens_details" => {
              "cached_tokens" => 800,
              "cache_write_tokens" => 600
            }
          },
          "output" => [ { "type" => "web_search_call" } ]
        }
      )

      response = described_class.generate_text_with_usage(
        prompt: "Summarise current evidence",
        api_key: "sk-test",
        model: "gpt-5.6-luna",
        reasoning: { effort: "none" },
        service_tier: "flex",
        prompt_cache_key: "notae-background-v1",
        prompt_cache_options: { ttl: "30m" }
      )

      expect(described_class).to have_received(:request_response!).with(
        hash_including(
          reasoning: { effort: "none" },
          service_tier: "flex",
          prompt_cache_key: "notae-background-v1",
          prompt_cache_options: { ttl: "30m" }
        )
      )
      expect(response[:usage]).to include(
        cached_prompt_tokens: 800,
        cache_write_tokens: 600,
        web_search_calls: 1,
        service_tier: "flex"
      )
    end

    it "keeps generate_text returning only the generated text" do
      allow(described_class).to receive(:generate_text_with_usage).and_return(
        text: "Concise answer",
        usage: { prompt_tokens: 2, completion_tokens: 2, total_tokens: 4 },
        sources: []
      )

      expect(described_class.generate_text(prompt: "Question", api_key: "sk-test")).to eq("Concise answer")
    end
  end

  describe ".extract_function_calls" do
    it "keeps malformed argument text available without raising" do
      calls = described_class.extract_function_calls(
        "output" => [
          { "type" => "function_call", "call_id" => "call_bad", "name" => "broken", "arguments" => "{bad" },
          { "type" => "message", "content" => [] }
        ]
      )

      expect(calls).to eq(
        [
          {
            call_id: "call_bad",
            name: "broken",
            arguments: nil,
            raw_arguments: "{bad"
          }
        ]
      )
    end
  end

  describe ".extract_output_text" do
    it "joins output_text content segments when the convenience field is absent" do
      body = {
        "output" => [
          { "content" => [ { "type" => "output_text", "text" => "First" } ] },
          { "content" => [ { "type" => "output_text", "text" => "Second" } ] }
        ]
      }

      expect(described_class.extract_output_text(body)).to eq("First\nSecond")
    end
  end

  describe ".request_payload!" do
    it "uses the bounded environment-configured response read timeout" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("OPENAI_RESPONSES_READ_TIMEOUT_SECONDS", "90").and_return("420")
      response = Net::HTTPOK.new("1.1", "200", "OK")
      allow(response).to receive(:body).and_return(JSON.generate(id: "resp_123", output: []))
      http = instance_double(Net::HTTP, request: response)
      allow(Net::HTTP).to receive(:start).and_yield(http)

      described_class.request_payload!(payload: { model: "gpt-5.6-luna", input: "Hello" }, api_key: "sk-test")

      expect(Net::HTTP).to have_received(:start).with(
        described_class::API_URL.host,
        described_class::API_URL.port,
        use_ssl: true,
        open_timeout: 5,
        read_timeout: 300
      )
    end

    it "defaults invalid response read timeout configuration to 90 seconds" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("OPENAI_RESPONSES_READ_TIMEOUT_SECONDS", "90").and_return("invalid")

      expect(described_class.read_timeout_seconds).to eq(90)
    end

    it "redacts a credential echoed by a provider error" do
      api_key = "sk-super-secret"
      response = Net::HTTPBadRequest.new("1.1", "400", "Bad Request")
      allow(response).to receive(:body).and_return(
        JSON.generate(error: { message: "Credential #{api_key} was rejected" })
      )
      http = instance_double(Net::HTTP, request: response)
      allow(Net::HTTP).to receive(:start).and_yield(http)

      expect do
        described_class.request_payload!(payload: { model: "gpt-5.6-luna", input: "Hello" }, api_key: api_key)
      end.to raise_error(described_class::Error, "Credential [REDACTED] was rejected")
    end

    it "wraps invalid JSON responses in the client error type" do
      response = Net::HTTPOK.new("1.1", "200", "OK")
      allow(response).to receive(:body).and_return("not-json")
      http = instance_double(Net::HTTP, request: response)
      allow(Net::HTTP).to receive(:start).and_yield(http)

      expect do
        described_class.request_payload!(payload: { model: "gpt-5.6-luna", input: "Hello" }, api_key: "sk-test")
      end.to raise_error(described_class::Error, /Invalid response from responses API/)
    end
  end
end
