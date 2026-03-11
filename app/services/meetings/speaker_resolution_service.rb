require "digest"

module Meetings
  class SpeakerResolutionService
    SpeakerTurn = Struct.new(
      :position,
      :started_ms,
      :ended_ms,
      :speaker_key,
      :speaker_name,
      :speaker_fingerprint,
      :text,
      :confidence,
      keyword_init: true
    )

    def initialize(session:)
      @session = session
    end

    def resolve(turns:)
      normalized_turns = Array(turns)
      return [] if normalized_turns.empty?

      aliases_by_fingerprint = MeetingSpeakerAlias
                                 .for_workspace(session.workspace)
                                 .index_by(&:speaker_fingerprint)
      invitee_fallback_names = invitee_fallback_name_by_speaker_key(normalized_turns)

      normalized_turns.map.with_index do |turn, index|
        speaker_key = turn.speaker_key.to_s.presence || "S#{index + 1}"
        fingerprint = self.class.fingerprint_for(session: session, speaker_key: speaker_key)
        alias_record = aliases_by_fingerprint[fingerprint]
        speaker_name =
          alias_record&.display_name.presence ||
          speaker_name_for(turn) ||
          invitee_fallback_names[speaker_key].presence ||
          fallback_speaker_name(speaker_key)

        create_invitee_match_alias!(fingerprint: fingerprint, speaker_name: speaker_name) if alias_record.blank? && invitee_fallback_names[speaker_key].present?

        SpeakerTurn.new(
          position: turn.position.to_i,
          started_ms: turn.started_ms,
          ended_ms: turn.ended_ms,
          speaker_key: speaker_key,
          speaker_name: speaker_name,
          speaker_fingerprint: fingerprint,
          text: turn.text.to_s.strip,
          confidence: turn.confidence
        )
      end
    end

    def apply_manual_mapping!(mapping)
      mapping.each do |speaker_key, display_name|
        name = display_name.to_s.strip
        next if name.blank?

        fingerprint = self.class.fingerprint_for(session: session, speaker_key: speaker_key)
        alias_record = MeetingSpeakerAlias.find_or_initialize_by(
          workspace_id: session.workspace_id,
          speaker_fingerprint: fingerprint
        )
        alias_record.display_name = name
        alias_record.source = "manual"
        alias_record.email = nil
        alias_record.metadata_json = alias_record.metadata_json.to_h
        alias_record.save!
      end

      refresh_session_utterance_names!
    end

    def self.fingerprint_for(session:, speaker_key:)
      Digest::SHA256.hexdigest("meeting-session-speaker:#{session.id}:#{speaker_key}")
    end

    private

    attr_reader :session

    def invitee_fallback_name_by_speaker_key(turns)
      unique_keys = turns.map { |turn| turn.speaker_key.to_s }.reject(&:blank?).uniq
      invitees = Array(session.kalendarium_event&.invitees)
      return {} if invitees.empty?

      mapped_names = invitees.map { |invitee| invitee["name"].to_s.strip.presence || invitee["email"].to_s.strip.presence }.compact
      unique_keys.each_with_index.each_with_object({}) do |(speaker_key, index), memo|
        memo[speaker_key] = mapped_names[index] if mapped_names[index].present?
      end
    end

    def speaker_name_for(turn)
      return unless turn.respond_to?(:speaker_name)

      turn.speaker_name.to_s.strip.presence
    end

    def create_invitee_match_alias!(fingerprint:, speaker_name:)
      MeetingSpeakerAlias.find_or_create_by!(
        workspace_id: session.workspace_id,
        speaker_fingerprint: fingerprint
      ) do |alias_record|
        alias_record.display_name = speaker_name
        alias_record.source = "invitee_match"
        alias_record.metadata_json = { "meeting_session_id" => session.id.to_s }
      end
    rescue ActiveRecord::RecordInvalid
      nil
    end

    def refresh_session_utterance_names!
      aliases = MeetingSpeakerAlias
                  .for_workspace(session.workspace)
                  .pluck(:speaker_fingerprint, :display_name)
                  .to_h
      session.meeting_utterances.find_each do |utterance|
        fingerprint = self.class.fingerprint_for(session: session, speaker_key: utterance.speaker_key)
        next if aliases[fingerprint].blank?

        utterance.update_columns(speaker_name: aliases[fingerprint], updated_at: Time.current)
      end
    end

    def fallback_speaker_name(speaker_key)
      number = speaker_key.to_s.delete_prefix("S").to_i
      number = 1 if number <= 0
      "Speaker #{number}"
    end
  end
end
