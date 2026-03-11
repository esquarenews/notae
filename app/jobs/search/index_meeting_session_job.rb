module Search
  class IndexMeetingSessionJob < ApplicationJob
    queue_as :default

    def perform(meeting_session_id)
      meeting_session = MeetingSession.find_by(id: meeting_session_id)

      if meeting_session.present?
        Search::ChunkIndexingService.index_meeting_session!(meeting_session: meeting_session)
      else
        Search::ChunkIndexingService.delete_source!(source_type: SearchChunk::SOURCE_MEETING_SESSION, source_id: meeting_session_id)
      end
    end
  end
end
