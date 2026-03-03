module Meetings
  class GenerateActionProposalsJob < ApplicationJob
    queue_as :default

    def perform(meeting_session_id)
      session = MeetingSession.find_by(id: meeting_session_id)
      return if session.blank?

      Meetings::ActionProposalService.new(session: session, actor: session.created_by).call
      session.update!(status: "completed", processed_at: Time.current, error_message: nil)
      Meetings::PurgeRawCaptureJob.perform_later(session.id)
    rescue StandardError => error
      session&.update(status: "failed", error_message: error.message, processed_at: Time.current)
    end
  end
end
