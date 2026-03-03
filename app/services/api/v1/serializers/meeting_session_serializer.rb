module Api
  module V1
    module Serializers
      class MeetingSessionSerializer
        def self.render_collection(sessions)
          sessions.map { |session| render(session) }
        end

        def self.render(session)
          {
            id: session.id,
            workspace_id: session.workspace_id,
            kalendarium_event_id: session.kalendarium_event_id,
            page_id: session.page_id,
            title: session.title,
            join_url: session.join_url,
            capture_mode: session.capture_mode,
            provider: session.provider,
            status: session.status,
            started_at: session.started_at&.iso8601(6),
            ended_at: session.ended_at&.iso8601(6),
            processed_at: session.processed_at&.iso8601(6),
            transcript_present: session.transcript_text.to_s.strip.present?,
            summary_present: session.summary_markdown.to_s.strip.present?,
            action_items_count: Array(session.action_items_json).length,
            created_at: session.created_at&.iso8601(6),
            updated_at: session.updated_at&.iso8601(6)
          }
        end
      end
    end
  end
end
