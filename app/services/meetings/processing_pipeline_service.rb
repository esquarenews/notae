require "tempfile"

module Meetings
  class ProcessingPipelineService
    class Error < StandardError; end
    DIARIZATION_MODEL = "gpt-4o-transcribe-diarize".freeze
    FALLBACK_MODEL = "gpt-4o-mini-transcribe".freeze

    def initialize(session:)
      @session = session
    end

    def call
      raise Error, "Meeting session capture file is missing" unless capture_attachment.present?
      raise Error, "OpenAI API key is not configured for this user" unless session.created_by.openai_api_key_configured?

      session.update!(status: "processing", error_message: nil)
      transcription = transcribe_capture_file!
      turns = turns_from_transcription(transcription)
      resolved_turns = Meetings::SpeakerResolutionService.new(session: session).resolve(turns: turns)

      MeetingSession.transaction do
        session.meeting_utterances.delete_all
        resolved_turns.each do |turn|
          session.meeting_utterances.create!(
            position: turn.position,
            started_ms: turn.started_ms,
            ended_ms: turn.ended_ms,
            speaker_key: turn.speaker_key,
            speaker_name: turn.speaker_name,
            text: turn.text,
            confidence: turn.confidence
          )
        end

        session.update!(
          transcript_text: transcript_for(resolved_turns),
          status: "summarizing",
          error_message: nil
        )
      end

      session
    rescue Openai::AudioTranscriptionsClient::Error => error
      raise Error, error.message
    rescue ActiveRecord::RecordInvalid => error
      raise Error, error.record.errors.full_messages.to_sentence
    end

    private

    attr_reader :session

    def capture_attachment
      @capture_attachment ||= session.capture_files.attachments.first
    end

    def transcribe_capture_file!
      downloaded_path = Tempfile.create([ "meeting-capture-#{session.id}", capture_extension ], binmode: true)
      downloaded_path.write(capture_attachment.blob.download)
      downloaded_path.flush

      response = transcribe_with_preferred_formats(downloaded_path.path)
      log_transcription_usage!(response)
      transcript_text = response["text"].to_s.strip
      normalized_segments = normalize_segments(response, transcript_text)

      {
        text: transcript_text,
        segments: normalized_segments.fetch(:segments),
        segments_source: normalized_segments.fetch(:source)
      }
    ensure
      downloaded_path&.close
      downloaded_path&.unlink if downloaded_path.respond_to?(:unlink)
    end

    def transcribe_with_preferred_formats(file_path)
      last_error = nil

      preferred_transcription_models.each do |model|
        transcription_attempts_for_model(model).each do |attempt|
          begin
            response = Openai::AudioTranscriptionsClient.transcribe(
              file_path: file_path,
              api_key: session.created_by.openai_api_key,
              model: model,
              response_format: attempt.fetch(:response_format),
              chunking_strategy: attempt[:chunking_strategy]
            )
            @last_transcription_model = model
            return response
          rescue Openai::AudioTranscriptionsClient::Error => error
            last_error = error
            raise error unless retry_with_fallback_format?(model: model, response_format: attempt.fetch(:response_format), message: error.message)
          end
        end
      end

      raise last_error if last_error
      raise Error, "Audio transcription request failed"
    end

    def preferred_transcription_models
      [
        ENV.fetch("OPENAI_MEETINGS_TRANSCRIPTION_MODEL", "").to_s.strip.presence,
        DIARIZATION_MODEL,
        ENV.fetch("OPENAI_TRANSCRIPTION_MODEL", "").to_s.strip.presence,
        FALLBACK_MODEL,
        "whisper-1"
      ].compact.uniq
    end

    def transcription_attempts_for_model(model)
      if diarization_model?(model)
        [
          { response_format: "diarized_json", chunking_strategy: "auto" },
          { response_format: "json", chunking_strategy: "auto" }
        ]
      else
        [
          { response_format: "verbose_json" },
          { response_format: "json" }
        ]
      end
    end

    def retry_with_fallback_format?(model:, response_format:, message:)
      return true if diarization_model?(model) && response_format == "diarized_json"

      normalized = message.to_s.downcase
      normalized.include?("response_format") ||
        normalized.include?("diarized_json") ||
        normalized.include?("timestamp_granularit") ||
        normalized.include?("chunking_strategy") ||
        normalized.include?("not compatible") ||
        ((normalized.include?("model") || normalized.include?("engine")) &&
          (normalized.include?("not found") || normalized.include?("not available") || normalized.include?("does not exist")))
    end

    def log_transcription_usage!(response_payload)
      usage = transcription_usage_from_response(response_payload)
      return if usage.blank?

      Search::AiUsageLogger.log!(
        user: session.created_by,
        workspace: session.workspace,
        operation: AiUsageLog::OP_MEETING_TRANSCRIPTION,
        model: @last_transcription_model.presence || preferred_transcription_models.first,
        usage: usage,
        metadata: {
          feature: "meetings_transcription",
          meeting_session_id: session.id
        }
      )
    end

    def transcription_usage_from_response(response_payload)
      usage = if response_payload.is_a?(Hash)
        response_payload["usage"] || response_payload[:usage]
      end
      return nil unless usage.respond_to?(:[])

      prompt_tokens = usage["input_tokens"] || usage[:input_tokens] || usage["prompt_tokens"] || usage[:prompt_tokens] || 0
      completion_tokens = usage["output_tokens"] || usage[:output_tokens] || usage["completion_tokens"] || usage[:completion_tokens] || 0
      total_tokens = usage["total_tokens"] || usage[:total_tokens]
      total_tokens = prompt_tokens.to_i + completion_tokens.to_i if total_tokens.blank?

      normalized = {
        prompt_tokens: prompt_tokens.to_i,
        completion_tokens: completion_tokens.to_i,
        total_tokens: total_tokens.to_i
      }
      return nil if normalized[:prompt_tokens].zero? && normalized[:completion_tokens].zero? && normalized[:total_tokens].zero?

      normalized
    end

    def diarization_model?(model)
      model.to_s.include?("diarize")
    end

    def turns_from_transcription(transcription)
      segments = Array(transcription[:segments])
      return [] if segments.empty?

      if segments_with_speakers?(segments)
        turns_from_speaker_segments(segments)
      elsif transcription[:segments_source] == :synthetic
        turns_from_synthetic_segments(segments)
      else
        Meetings::LocalDiarizer.call(segments: segments)
      end
    end

    def segments_with_speakers?(segments)
      segments.any? { |segment| segment[:speaker].to_s.strip.present? }
    end

    def turns_from_speaker_segments(segments)
      speaker_keys = {}
      segments.map.with_index do |segment, index|
        speaker_label = segment[:speaker].to_s.strip
        speaker_label = "speaker_#{index + 1}" if speaker_label.blank?
        speaker_key = speaker_keys[speaker_label] ||= "S#{speaker_keys.length + 1}"

        started_ms = (segment[:start].to_f * 1000).to_i
        ended_ms = (segment[:end].to_f * 1000).to_i
        ended_ms = [ ended_ms, started_ms + 220 ].max

        Meetings::LocalDiarizer::Turn.new(
          position: index,
          started_ms: started_ms,
          ended_ms: ended_ms,
          speaker_key: speaker_key,
          text: segment[:text].to_s.strip,
          confidence: 0.78
        )
      end
    end

    def turns_from_synthetic_segments(segments)
      speaker_count = estimated_speaker_count
      segments.map.with_index do |segment, index|
        Meetings::LocalDiarizer::Turn.new(
          position: index,
          started_ms: (segment[:start].to_f * 1000).to_i,
          ended_ms: (segment[:end].to_f * 1000).to_i,
          speaker_key: "S#{(index % speaker_count) + 1}",
          text: segment[:text].to_s.strip,
          confidence: 0.48
        )
      end
    end

    def estimated_speaker_count
      invitees = Array(session.kalendarium_event&.invitees)
      count = [ invitees.size, 1 ].max
      [ count, 4 ].min
    end

    def normalize_segments(raw_response, transcript_text)
      payload = raw_response.is_a?(Hash) ? raw_response : {}

      segments = Array(payload["segments"]).filter_map do |segment|
        text = segment_value(segment, "text").to_s.strip
        next if text.blank?

        start_time = segment_value(segment, "start").to_f
        end_time = segment_value(segment, "end").to_f
        end_time = [ end_time, start_time ].max

        {
          start: start_time,
          end: end_time,
          text: text,
          speaker: speaker_label_for(segment)
        }
      end

      return { segments: segments, source: :provider } if segments.any?

      word_segments = segments_from_words(Array(payload["words"]))
      return { segments: word_segments, source: :provider_words } if word_segments.any?

      fallback_segments = sentence_segments_from_text(transcript_text)
      return { segments: fallback_segments, source: :synthetic } if fallback_segments.any?

      fallback_text = transcript_text.to_s.presence || "Transcript unavailable."
      { segments: [ { start: 0.0, end: 1.0, text: fallback_text } ], source: :fallback }
    end

    def segment_value(segment, key)
      segment[key] || segment[key.to_sym]
    end

    def speaker_label_for(segment)
      value = segment_value(segment, "speaker")
      if value.is_a?(Hash)
        segment_value(value, "name") || segment_value(value, "id") || segment_value(value, "label")
      else
        value
      end
    end

    def segments_from_words(words)
      entries = words.filter_map do |word|
        token = segment_value(word, "word").to_s.presence || segment_value(word, "text").to_s.presence
        next if token.blank?

        {
          speaker: speaker_label_for(word).to_s.strip.presence,
          start: segment_value(word, "start").to_f,
          end: segment_value(word, "end").to_f,
          text: token.strip
        }
      end
      return [] if entries.empty?
      return [] if entries.none? { |entry| entry[:speaker].present? }

      grouped = []
      current = nil
      entries.each do |entry|
        if current.nil? || entry[:speaker] != current[:speaker]
          grouped << {
            speaker: entry[:speaker],
            start: entry[:start],
            end: [ entry[:end], entry[:start] ].max,
            text: entry[:text]
          }
          current = grouped.last
        else
          current[:end] = [ entry[:end], current[:end] ].max
          current[:text] = [ current[:text], entry[:text] ].join(" ")
        end
      end

      grouped
    end

    def sentence_segments_from_text(text)
      content = text.to_s.strip
      return [] if content.blank?

      sentences = content.split(/(?<=[.!?])\s+|\n+/).map(&:strip).reject(&:blank?)
      if sentences.length < 2
        chunked = content.split(/\s+/).each_slice(16).map { |words| words.join(" ").strip }.reject(&:blank?)
        sentences = chunked if chunked.length > 1
      end
      return [] if sentences.length < 2

      cursor = 0.0
      sentences.map do |sentence|
        words = [ sentence.scan(/\S+/).length, 1 ].max
        duration = [ words * 0.42, 1.1 ].max
        segment = {
          start: cursor,
          end: cursor + duration,
          text: sentence
        }
        cursor += duration + 0.08
        segment
      end
    end

    def transcript_for(turns)
      Array(turns).map do |turn|
        timestamp = milliseconds_to_clock(turn.started_ms.to_i)
        speaker = turn.speaker_name.to_s.presence || turn.speaker_key
        "[#{timestamp}] #{speaker}: #{turn.text}"
      end.join("\n")
    end

    def milliseconds_to_clock(value)
      seconds = [ value / 1000, 0 ].max
      minutes = seconds / 60
      remaining_seconds = seconds % 60
      format("%02d:%02d", minutes, remaining_seconds)
    end

    def capture_extension
      filename = capture_attachment&.filename.to_s
      ext = File.extname(filename)
      ext.present? ? ext : ".webm"
    end
  end
end
