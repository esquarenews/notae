require "json"
require "net/http"
require "uri"

module Openai
  class EmbeddingsClient
    API_URL = URI("https://api.openai.com/v1/embeddings")

    class Error < StandardError; end

    def self.embed(text:, api_key:, model: SearchChunk::EMBEDDING_MODEL)
      vectors = embed_many(texts: [ text ], api_key: api_key, model: model)
      vectors.first || []
    end

    def self.embed_many(texts:, api_key:, model: SearchChunk::EMBEDDING_MODEL)
      normalized_inputs = Array(texts).map { |value| value.to_s.strip }.reject(&:blank?)
      return [] if normalized_inputs.empty?
      raise Error, "Missing OpenAI API key" if api_key.to_s.strip.blank?

      body = request_embeddings!(inputs: normalized_inputs, api_key: api_key, model: model)
      data = body.fetch("data")

      data.sort_by { |item| item.fetch("index") }
          .map { |item| item.fetch("embedding").map(&:to_f) }
    end

    def self.request_embeddings!(inputs:, api_key:, model:)
      request = Net::HTTP::Post.new(API_URL)
      request["Authorization"] = "Bearer #{api_key}"
      request["Content-Type"] = "application/json"
      request.body = JSON.generate({ model: model, input: inputs })

      response = Net::HTTP.start(
        API_URL.host,
        API_URL.port,
        use_ssl: true,
        open_timeout: 5,
        read_timeout: 20
      ) do |http|
        http.request(request)
      end

      parsed = JSON.parse(response.body)

      return parsed if response.is_a?(Net::HTTPSuccess)

      message = parsed.dig("error", "message") || "OpenAI embeddings request failed"
      raise Error, message
    rescue JSON::ParserError => e
      raise Error, "Invalid response from embeddings API: #{e.message}"
    rescue Timeout::Error, SocketError, Errno::ECONNREFUSED => e
      raise Error, "Embeddings API connection failed: #{e.message}"
    end
  end
end
