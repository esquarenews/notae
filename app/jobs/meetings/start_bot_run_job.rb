module Meetings
  class StartBotRunJob < ApplicationJob
    queue_as :default

    def perform(meeting_bot_run_id)
      run = MeetingBotRun.find_by(id: meeting_bot_run_id)
      return if run.blank?
      return unless run.status == "queued"

      run.update!(status: "joining")
      run.meeting_session.update!(status: "joining", error_message: nil)
    rescue StandardError => error
      run&.update(status: "failed", error_message: error.message, finished_at: Time.current)
      run&.meeting_session&.update(status: "failed", error_message: error.message)
    end
  end
end
