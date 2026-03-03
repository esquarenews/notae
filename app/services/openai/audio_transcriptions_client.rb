require "json"
require "net/http"
require "uri"

module Openai
  class AudioTranscriptionsClient
    API_URL = URI("https://api.openai.com/v1/audio/transcriptions")

    class Error < StandardError; end

    def self.transcribe(file_path:, api_key:, model: nil, prompt: nil, language: nil)
      raise Error, "Missing OpenAI API key" if api_key.to_s.strip.blank?
      raise Error, "Audio file not found" unless File.exist?(file_path.to_s)

      chosen_model = model.to_s.strip.presence || ENV.fetch("OPENAI_TRANSCRIPTION_MODEL", "gpt-4o-mini-transcribe")
      boundary = "----NotaeMeetingBoundary#{SecureRandom.hex(12)}"
      body = multipart_body(
        boundary: boundary,
        file_path: file_path,
        model: chosen_model,
        prompt: prompt,
        language: language
      )

      request = Net::HTTP::Post.new(API_URL)
      request["Authorization"] = "Bearer #{api_key}"
      request["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
      request.body = body

      response = Net::HTTP.start(
        API_URL.host,
        API_URL.port,
        use_ssl: true,
        open_timeout: 8,
        read_timeout: 120
      ) { |http| http.request(request) }

      parsed = JSON.parse(response.body)
      return parsed if response.is_a?(Net::HTTPSuccess)

      message = parsed.dig("error", "message").presence || "Audio transcription request failed"
      raise Error, message
    rescue JSON::ParserError => error
      raise Error, "Invalid response from transcription API: #{error.message}"
    rescue Timeout::Error, SocketError, Errno::ECONNREFUSED => error
      raise Error, "Transcription API connection failed: #{error.message}"
    end

    def self.multipart_body(boundary:, file_path:, model:, prompt:, language:)
      filename = File.basename(file_path)
      mime_type = mime_type_for(filename)
      file_bytes = File.binread(file_path)
      parts = []
      append_part(parts, boundary, "model", model)
      append_part(parts, boundary, "response_format", "verbose_json")
      append_part(parts, boundary, "timestamp_granularities[]", "segment")
      append_part(parts, boundary, "prompt", prompt.to_s) if prompt.to_s.present?
      append_part(parts, boundary, "language", language.to_s) if language.to_s.present?
      parts << "--#{boundary}\r\n"
      parts << %(Content-Disposition: form-data; name="file"; filename="#{filename}"\r\n)
      parts << "Content-Type: #{mime_type}\r\n\r\n"
      parts << file_bytes
      parts << "\r\n"
      parts << "--#{boundary}--\r\n"
      parts.join
    end

    def self.append_part(parts, boundary, name, value)
      parts << "--#{boundary}\r\n"
      parts << %(Content-Disposition: form-data; name="#{name}"\r\n\r\n)
      parts << value.to_s
      parts << "\r\n"
    end

    def self.mime_type_for(filename)
      extension = File.extname(filename).downcase
      case extension
      when ".wav"
        "audio/wav"
      when ".mp3"
        "audio/mpeg"
      when ".m4a"
        "audio/mp4"
      when ".mp4"
        "video/mp4"
      when ".webm"
        "audio/webm"
      else
        "application/octet-stream"
      end
    end
  end
end
