module Meetings
  class GuardBotRunJob < ApplicationJob
    queue_as :default

    GUARD_INTERVAL = 2.minutes
    CLAIM_TIMEOUT = 2.minutes
    JOIN_TIMEOUT = 12.minutes
    HEARTBEAT_TIMEOUT = 2.minutes

    def perform(meeting_bot_run_id)
      run = MeetingBotRun.includes(:meeting_session).find_by(id: meeting_bot_run_id)
      return if run.blank?
      return unless run.status.in?(%w[queued claimed joining recording uploading])

      failure_message = failure_message_for(run)
      if failure_message.present?
        fail_run!(run, failure_message)
        return
      end

      self.class.set(wait: GUARD_INTERVAL).perform_later(run.id)
    end

    private

    def failure_message_for(run)
      session = run.meeting_session
      return "Meeting session is no longer active." if session.blank? || session.status.in?(%w[cancelled completed failed])

      now = Time.current

      case run.status
      when "queued"
        return "Meeting bot worker did not claim the run." if run.created_at <= now - CLAIM_TIMEOUT
      when "claimed"
        return "Meeting bot worker claimed the run but did not begin joining." if run.claimed_at.present? && run.claimed_at <= now - CLAIM_TIMEOUT
        return "Meeting bot worker heartbeat timed out." if run.last_heartbeat_at.present? && run.last_heartbeat_at <= now - HEARTBEAT_TIMEOUT
      when "joining"
        return "Meeting bot worker heartbeat timed out while joining." if run.last_heartbeat_at.present? && run.last_heartbeat_at <= now - HEARTBEAT_TIMEOUT
        return "Meeting bot worker could not join the meeting." if run.claimed_at.present? && run.claimed_at <= now - JOIN_TIMEOUT
      when "recording", "uploading"
        return "Meeting bot worker heartbeat timed out." if run.last_heartbeat_at.present? && run.last_heartbeat_at <= now - HEARTBEAT_TIMEOUT
      end

      nil
    end

    def fail_run!(run, message)
      run.update!(
        status: "failed",
        finished_at: Time.current,
        error_message: message
      )
      run.meeting_session.update!(
        status: "failed",
        error_message: message,
        ended_at: Time.current
      )
    end
  end
end
