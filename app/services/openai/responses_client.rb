require "json"
require "net/http"
require "uri"

module Openai
  class ResponsesClient
    API_URL = URI("https://api.openai.com/v1/responses")
    DEFAULT_READ_TIMEOUT_SECONDS = 90
    MIN_READ_TIMEOUT_SECONDS = 5
    MAX_READ_TIMEOUT_SECONDS = 300

    class Error < StandardError; end

    def self.create(
      input:,
      api_key:,
      model:,
      instructions: nil,
      tools: nil,
      include: nil,
      previous_response_id: nil,
      reasoning: nil,
      text: nil,
      parallel_tool_calls: nil,
      safety_identifier: nil,
      max_output_tokens: nil,
      service_tier: nil,
      prompt_cache_key: nil,
      prompt_cache_options: nil
    )
      normalized_api_key = api_key.to_s.strip
      normalized_model = model.to_s.strip
      raise Error, "Missing OpenAI API key" if normalized_api_key.blank?
      raise Error, "Missing OpenAI model" if normalized_model.blank?

      payload = {
        model: normalized_model,
        input: input
      }
      payload[:instructions] = instructions unless instructions.nil?
      payload[:tools] = tools unless tools.nil?
      payload[:include] = include unless include.nil?
      payload[:previous_response_id] = previous_response_id if previous_response_id.present?
      payload[:reasoning] = reasoning unless reasoning.nil?
      payload[:text] = text unless text.nil?
      payload[:parallel_tool_calls] = parallel_tool_calls unless parallel_tool_calls.nil?
      payload[:safety_identifier] = safety_identifier if safety_identifier.present?
      payload[:max_output_tokens] = max_output_tokens unless max_output_tokens.nil?
      payload[:service_tier] = service_tier if service_tier.present?
      payload[:prompt_cache_key] = prompt_cache_key if prompt_cache_key.present?
      payload[:prompt_cache_options] = prompt_cache_options unless prompt_cache_options.nil?

      body = request_payload!(payload: payload, api_key: normalized_api_key)
      response_from_body(body)
    end

    def self.generate_text(
      prompt:,
      api_key:,
      model: "gpt-4o-mini",
      max_output_tokens: 260,
      tools: nil,
      include: nil,
      reasoning: nil,
      service_tier: nil,
      prompt_cache_key: nil,
      prompt_cache_options: nil
    )
      response = generate_text_with_usage(
        prompt: prompt,
        api_key: api_key,
        model: model,
        max_output_tokens: max_output_tokens,
        tools: tools,
        include: include,
        reasoning: reasoning,
        service_tier: service_tier,
        prompt_cache_key: prompt_cache_key,
        prompt_cache_options: prompt_cache_options
      )
      response[:text]
    end

    def self.generate_text_with_usage(
      prompt:,
      api_key:,
      model: "gpt-4o-mini",
      max_output_tokens: 260,
      tools: nil,
      include: nil,
      reasoning: nil,
      service_tier: nil,
      prompt_cache_key: nil,
      prompt_cache_options: nil
    )
      normalized_prompt = prompt.to_s.strip
      return { text: "", usage: default_usage, sources: [] } if normalized_prompt.blank?
      raise Error, "Missing OpenAI API key" if api_key.to_s.strip.blank?

      body = request_response!(
        prompt: normalized_prompt,
        api_key: api_key,
        model: model,
        max_output_tokens: max_output_tokens,
        tools: tools,
        include: include,
        reasoning: reasoning,
        service_tier: service_tier,
        prompt_cache_key: prompt_cache_key,
        prompt_cache_options: prompt_cache_options
      )

      normalized_usage = usage_from_body(body)
      normalized_usage[:service_tier] ||= service_tier if service_tier.present?

      {
        text: extract_output_text(body),
        usage: normalized_usage,
        sources: extract_sources(body)
      }
    end

    def self.request_response!(
      prompt:,
      api_key:,
      model:,
      max_output_tokens:,
      tools: nil,
      include: nil,
      reasoning: nil,
      service_tier: nil,
      prompt_cache_key: nil,
      prompt_cache_options: nil
    )
      payload = {
        model: model,
        input: prompt,
        max_output_tokens: max_output_tokens
      }
      payload[:tools] = tools if tools.present?
      payload[:include] = include if include.present?
      payload[:reasoning] = reasoning unless reasoning.nil?
      payload[:service_tier] = service_tier if service_tier.present?
      payload[:prompt_cache_key] = prompt_cache_key if prompt_cache_key.present?
      payload[:prompt_cache_options] = prompt_cache_options unless prompt_cache_options.nil?

      request_payload!(payload: payload, api_key: api_key)
    end

    def self.request_payload!(payload:, api_key:)
      request = Net::HTTP::Post.new(API_URL)
      request["Authorization"] = "Bearer #{api_key}"
      request["Content-Type"] = "application/json"
      request.body = JSON.generate(payload)

      response = Net::HTTP.start(
        API_URL.host,
        API_URL.port,
        use_ssl: true,
        open_timeout: 5,
        read_timeout: read_timeout_seconds
      ) do |http|
        http.request(request)
      end

      parsed = JSON.parse(response.body)
      return parsed if response.is_a?(Net::HTTPSuccess)

      message = parsed.dig("error", "message") || "OpenAI responses request failed"
      raise Error, redact_api_key(message, api_key)
    rescue JSON::ParserError => e
      raise Error, "Invalid response from responses API: #{e.message}"
    rescue Timeout::Error,
           SocketError,
           EOFError,
           IOError,
           Errno::ECONNREFUSED,
           Errno::ECONNRESET,
           Errno::EHOSTUNREACH,
           Errno::ENETUNREACH,
           OpenSSL::SSL::SSLError => e
      raise Error, "Responses API connection failed: #{redact_api_key(e.message, api_key)}"
    end

    def self.response_from_body(body)
      {
        id: body["id"].to_s.presence,
        text: extract_output_text(body),
        function_calls: extract_function_calls(body),
        usage: usage_from_body(body),
        sources: extract_sources(body),
        raw: body
      }
    end

    def self.extract_output_text(body)
      output_text = body["output_text"].to_s.strip
      return output_text if output_text.present?

      segments = Array(body["output"]).flat_map do |entry|
        Array(entry["content"]).filter_map { |content| content["text"].to_s if content["type"] == "output_text" }
      end

      segments.join("\n").strip
    end

    def self.usage_from_body(body)
      usage = body.fetch("usage", {})
      prompt_tokens = usage.fetch("input_tokens", usage.fetch("prompt_tokens", 0)).to_i
      completion_tokens = usage.fetch("output_tokens", usage.fetch("completion_tokens", 0)).to_i
      total_tokens = usage.fetch("total_tokens", prompt_tokens + completion_tokens).to_i
      input_details = usage.fetch("input_tokens_details", usage.fetch("prompt_tokens_details", {}))
      cached_prompt_tokens = input_details.fetch("cached_tokens", 0).to_i
      cache_write_tokens = input_details.fetch("cache_write_tokens", 0).to_i
      web_search_calls = Array(body["output"]).count { |entry| entry["type"] == "web_search_call" }

      normalized = {
        prompt_tokens: prompt_tokens,
        completion_tokens: completion_tokens,
        total_tokens: total_tokens
      }
      normalized[:cached_prompt_tokens] = cached_prompt_tokens if cached_prompt_tokens.positive?
      normalized[:cache_write_tokens] = cache_write_tokens if cache_write_tokens.positive?
      normalized[:web_search_calls] = web_search_calls if web_search_calls.positive?
      normalized[:service_tier] = body["service_tier"].to_s if body["service_tier"].present?
      normalized
    end

    def self.default_usage
      {
        prompt_tokens: 0,
        completion_tokens: 0,
        total_tokens: 0
      }
    end

    def self.extract_function_calls(body)
      Array(body["output"]).filter_map do |entry|
        next unless entry["type"] == "function_call"

        raw_arguments = entry["arguments"].to_s
        function_call = {
          name: entry["name"].to_s,
          arguments: parse_function_arguments(raw_arguments),
          raw_arguments: raw_arguments
        }
        function_call[:id] = entry["id"].to_s if entry["id"].present?
        function_call[:call_id] = entry["call_id"].to_s if entry["call_id"].present?
        function_call[:status] = entry["status"].to_s if entry["status"].present?
        function_call
      end
    end

    def self.extract_sources(body)
      sources = []

      Array(body["sources"]).each do |source|
        normalized = normalize_source(source)
        sources << normalized if normalized.present?
      end

      Array(body["output"]).each do |entry|
        Array(entry.dig("action", "sources")).each do |source|
          normalized = normalize_source(source)
          sources << normalized if normalized.present?
        end

        Array(entry["content"]).each do |content|
          Array(content["annotations"]).each do |annotation|
            next unless annotation["type"] == "url_citation"

            normalized = normalize_source(annotation)
            sources << normalized if normalized.present?
          end
        end
      end

      sources.uniq { |source| source[:url] }
    end

    def self.normalize_source(source)
      url = source["url"].to_s.strip
      return nil if url.blank?

      title = source["title"].to_s.strip
      title = source["display_url"].to_s.strip if title.blank?
      title = source["site_name"].to_s.strip if title.blank?
      title = url if title.blank?

      {
        title: title,
        url: url
      }
    end

    def self.parse_function_arguments(raw_arguments)
      return {} if raw_arguments.blank?

      JSON.parse(raw_arguments)
    rescue JSON::ParserError
      nil
    end

    def self.redact_api_key(message, api_key)
      value = message.to_s
      secret = api_key.to_s
      return value if secret.blank?

      value.gsub(secret, "[REDACTED]")
    end

    def self.read_timeout_seconds
      configured = Integer(
        ENV.fetch("OPENAI_RESPONSES_READ_TIMEOUT_SECONDS", DEFAULT_READ_TIMEOUT_SECONDS.to_s),
        10
      )
      configured.clamp(MIN_READ_TIMEOUT_SECONDS, MAX_READ_TIMEOUT_SECONDS)
    rescue ArgumentError, TypeError
      DEFAULT_READ_TIMEOUT_SECONDS
    end
  end
end
