module Meetings
  class AutoStopSessionJob < ApplicationJob
    queue_as :default

    RESCHEDULE_THRESHOLD = 15.seconds
    AUTO_STOP_GRACE = Meetings::OnlineSessionScheduleService::AUTO_STOP_GRACE

    def perform(meeting_session_id)
      session = MeetingSession.includes(:kalendarium_event, :created_by, :updated_by).find_by(id: meeting_session_id)
      return if session.blank?
      return unless session.capture_mode == "online_bot"
      return unless session.status.in?(%w[scheduled joining recording])

      event = session.kalendarium_event
      return if event.blank?

      actor = session.updated_by || session.created_by
      if event.status == "cancelled"
        Meetings::StopSessionService.new(
          session: session,
          actor: actor,
          reason: "Meeting event was cancelled."
        ).call
        return
      end

      ends_at = event.ends_at_utc
      if ends_at.present? && ends_at + AUTO_STOP_GRACE > Time.current + RESCHEDULE_THRESHOLD
        self.class.set(wait_until: ends_at + AUTO_STOP_GRACE).perform_later(session.id)
        return
      end

      return unless session.status.in?(%w[joining recording])

      Meetings::StopSessionService.new(
        session: session,
        actor: actor,
        reason: "Meeting ended; capture stopped automatically."
      ).call
    end
  end
end
