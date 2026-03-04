module Meetings
  class ProcessSessionJob < ApplicationJob
    queue_as :default

    def perform(meeting_session_id)
      session = MeetingSession.find_by(id: meeting_session_id)
      return if session.blank?

      Meetings::ProcessingPipelineService.new(session: session).call
      Meetings::SummarizeSessionJob.perform_later(session.id)
    rescue Meetings::ProcessingPipelineService::Error => error
      session&.update(status: "failed", error_message: error.message, processed_at: Time.current, ended_at: Time.current)
    rescue StandardError => error
      session&.update(status: "failed", error_message: error.message, processed_at: Time.current, ended_at: Time.current)
    end
  end
end
