require "json"
require "net/http"
require "uri"

module Openai
  class ResponsesClient
    API_URL = URI("https://api.openai.com/v1/responses")

    class Error < StandardError; end

    def self.generate_text(prompt:, api_key:, model: "gpt-4o-mini", max_output_tokens: 260, tools: nil, include: nil)
      response = generate_text_with_usage(
        prompt: prompt,
        api_key: api_key,
        model: model,
        max_output_tokens: max_output_tokens,
        tools: tools,
        include: include
      )
      response[:text]
    end

    def self.generate_text_with_usage(prompt:, api_key:, model: "gpt-4o-mini", max_output_tokens: 260, tools: nil, include: nil)
      normalized_prompt = prompt.to_s.strip
      return { text: "", usage: default_usage, sources: [] } if normalized_prompt.blank?
      raise Error, "Missing OpenAI API key" if api_key.to_s.strip.blank?

      body = request_response!(
        prompt: normalized_prompt,
        api_key: api_key,
        model: model,
        max_output_tokens: max_output_tokens,
        tools: tools,
        include: include
      )

      {
        text: extract_output_text(body),
        usage: usage_from_body(body),
        sources: extract_sources(body)
      }
    end

    def self.request_response!(prompt:, api_key:, model:, max_output_tokens:, tools: nil, include: nil)
      request = Net::HTTP::Post.new(API_URL)
      request["Authorization"] = "Bearer #{api_key}"
      request["Content-Type"] = "application/json"
      payload = {
        model: model,
        input: prompt,
        max_output_tokens: max_output_tokens
      }
      payload[:tools] = tools if tools.present?
      payload[:include] = include if include.present?
      request.body = JSON.generate(payload)

      response = Net::HTTP.start(
        API_URL.host,
        API_URL.port,
        use_ssl: true,
        open_timeout: 5,
        read_timeout: 25
      ) do |http|
        http.request(request)
      end

      parsed = JSON.parse(response.body)
      return parsed if response.is_a?(Net::HTTPSuccess)

      message = parsed.dig("error", "message") || "OpenAI responses request failed"
      raise Error, message
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
      raise Error, "Responses API connection failed: #{e.message}"
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

      {
        prompt_tokens: prompt_tokens,
        completion_tokens: completion_tokens,
        total_tokens: total_tokens
      }
    end

    def self.default_usage
      {
        prompt_tokens: 0,
        completion_tokens: 0,
        total_tokens: 0
      }
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
  end
end
