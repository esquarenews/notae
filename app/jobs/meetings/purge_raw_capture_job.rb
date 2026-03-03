module Meetings
  class PurgeRawCaptureJob < ApplicationJob
    queue_as :default

    def perform(meeting_session_id)
      session = MeetingSession.find_by(id: meeting_session_id)
      return if session.blank?

      Meetings::RetentionService.new(session: session).purge_raw_captures!
    end
  end
end
