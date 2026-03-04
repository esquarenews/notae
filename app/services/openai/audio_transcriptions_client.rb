require "json"
require "net/http"
require "uri"

module Openai
  class AudioTranscriptionsClient
    API_URL = URI("https://api.openai.com/v1/audio/transcriptions")

    class Error < StandardError; end

    def self.transcribe(
      file_path:,
      api_key:,
      model: nil,
      prompt: nil,
      language: nil,
      response_format: nil,
      chunking_strategy: nil,
      known_speaker_names: nil,
      known_speaker_references: nil
    )
      raise Error, "Missing OpenAI API key" if api_key.to_s.strip.blank?
      raise Error, "Audio file not found" unless File.exist?(file_path.to_s)

      chosen_model = model.to_s.strip.presence || ENV.fetch("OPENAI_TRANSCRIPTION_MODEL", "gpt-4o-mini-transcribe")
      chosen_response_format = response_format.to_s.strip.presence || ENV.fetch("OPENAI_TRANSCRIPTION_RESPONSE_FORMAT", "json")
      boundary = "----NotaeMeetingBoundary#{SecureRandom.hex(12)}"
      body = multipart_body(
        boundary: boundary,
        file_path: file_path,
        model: chosen_model,
        response_format: chosen_response_format,
        prompt: prompt,
        language: language,
        chunking_strategy: chunking_strategy,
        known_speaker_names: known_speaker_names,
        known_speaker_references: known_speaker_references
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

    def self.multipart_body(
      boundary:,
      file_path:,
      model:,
      response_format:,
      prompt:,
      language:,
      chunking_strategy: nil,
      known_speaker_names: nil,
      known_speaker_references: nil
    )
      filename = File.basename(file_path)
      mime_type = mime_type_for(filename)
      file_bytes = File.binread(file_path)
      parts = []
      append_part(parts, boundary, "model", model)
      append_part(parts, boundary, "response_format", response_format)
      append_part(parts, boundary, "timestamp_granularities[]", "segment") if response_format == "verbose_json"
      append_part(parts, boundary, "prompt", prompt.to_s) if prompt.to_s.present?
      append_part(parts, boundary, "language", language.to_s) if language.to_s.present?
      append_part(parts, boundary, "chunking_strategy", chunking_strategy.to_s) if chunking_strategy.to_s.present?
      Array(known_speaker_names).each do |speaker_name|
        value = speaker_name.to_s.strip
        next if value.blank?

        append_part(parts, boundary, "known_speaker_names[]", value)
      end
      Array(known_speaker_references).each do |reference|
        value = reference.to_s.strip
        next if value.blank?

        append_part(parts, boundary, "known_speaker_references[]", value)
      end
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
