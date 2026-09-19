require "json"

module Search
  class AssistantModelRouter
    Route = Struct.new(:tier, :model, :reasoning_effort, :usage, keyword_init: true)

    TIERS = %w[luna terra sol].freeze
    REASONING_EFFORTS = %w[none low medium high xhigh max].freeze
    DEFAULT_TIER = "terra"
    DEFAULT_REASONING_BY_TIER = {
      "luna" => "none",
      "terra" => "medium",
      "sol" => "high"
    }.freeze
    DEFAULT_MODELS = {
      "luna" => "gpt-5.6-luna",
      "terra" => "gpt-5.6-terra",
      "sol" => "gpt-5.6-sol"
    }.freeze
    MODEL_ENV_KEYS = {
      "luna" => "OPENAI_ASSISTANT_MODEL_LUNA",
      "terra" => "OPENAI_ASSISTANT_MODEL_TERRA",
      "sol" => "OPENAI_ASSISTANT_MODEL_SOL"
    }.freeze

    ROUTING_INSTRUCTIONS = <<~INSTRUCTIONS.freeze
      Route the assistant request to one GPT-5.6 capability tier. Do not answer or execute the request.
      Judge the complete request and supplied context semantically, including ambiguity, reasoning depth,
      tool orchestration, consequence of errors, and how difficult the result will be to verify.

      Use luna for efficient, well-bounded work that needs little reasoning. Use terra for capable general
      work, synthesis, or multi-step tool use. Use sol for the hardest, most ambiguous, high-consequence,
      or deeply interconnected work. Choose the lowest tier likely to complete the request reliably.
      Do not make the decision from isolated words, phrases, or regex-like keyword matching.

      Select a reasoning effort supported by GPT-5.6: none, low, medium, high, xhigh, or max.
      Return only the JSON object required by the response schema.
    INSTRUCTIONS

    ROUTE_SCHEMA = {
      type: "json_schema",
      name: "assistant_model_route",
      strict: true,
      schema: {
        type: "object",
        properties: {
          tier: { type: "string", enum: TIERS },
          reasoning_effort: { type: "string", enum: REASONING_EFFORTS }
        },
        required: %w[tier reasoning_effort],
        additionalProperties: false
      }
    }.freeze

    class << self
      def model_for(tier)
        normalized_tier = tier.to_s.downcase
        normalized_tier = DEFAULT_TIER unless TIERS.include?(normalized_tier)
        configured = ENV[MODEL_ENV_KEYS.fetch(normalized_tier)].to_s.strip

        configured.presence || DEFAULT_MODELS.fetch(normalized_tier)
      end

      def router_model
        ENV["OPENAI_ASSISTANT_ROUTER_MODEL"].to_s.strip.presence || model_for("luna")
      end
    end

    def initialize(api_key:, safety_identifier: nil)
      @api_key = api_key
      @safety_identifier = safety_identifier
    end

    def call(request:, context: {})
      return fallback_route if request.to_s.strip.blank?

      response = Openai::ResponsesClient.create(
        input: JSON.generate(
          request: request.to_s.strip,
          context: context.presence || {}
        ),
        instructions: ROUTING_INSTRUCTIONS,
        api_key: api_key,
        model: self.class.router_model,
        reasoning: { effort: "none" },
        text: { format: ROUTE_SCHEMA },
        safety_identifier: safety_identifier,
        prompt_cache_key: "notae-assistant-router-v1",
        prompt_cache_options: { ttl: "30m" },
        max_output_tokens: 120
      )

      route_from(response)
    rescue Openai::ResponsesClient::Error, JSON::ParserError, TypeError, KeyError
      fallback_route
    end

    private

    attr_reader :api_key, :safety_identifier

    def route_from(response)
      payload = JSON.parse(response.fetch(:text).to_s)
      tier = payload.fetch("tier").to_s.downcase
      raise KeyError, "Unsupported assistant model tier" unless TIERS.include?(tier)

      reasoning_effort = payload["reasoning_effort"].to_s.downcase
      reasoning_effort = DEFAULT_REASONING_BY_TIER.fetch(tier) unless REASONING_EFFORTS.include?(reasoning_effort)

      Route.new(
        tier: tier,
        model: self.class.model_for(tier),
        reasoning_effort: reasoning_effort,
        usage: response[:usage] || Openai::ResponsesClient.default_usage
      )
    end

    def fallback_route
      Route.new(
        tier: DEFAULT_TIER,
        model: self.class.model_for(DEFAULT_TIER),
        reasoning_effort: DEFAULT_REASONING_BY_TIER.fetch(DEFAULT_TIER),
        usage: Openai::ResponsesClient.default_usage
      )
    end
  end
end
