module Meetings
  class DispatchScheduledSessionJob < ApplicationJob
    queue_as :default

    RESCHEDULE_THRESHOLD = 15.seconds

    def perform(meeting_session_id)
      session = MeetingSession.includes(:kalendarium_event, :created_by, :updated_by).find_by(id: meeting_session_id)
      return if session.blank?
      return unless session.capture_mode == "online_bot"
      return unless session.status == "scheduled"

      event = session.kalendarium_event
      return if event.blank?

      if event.status == "cancelled"
        session.update!(
          status: "cancelled",
          ended_at: Time.current,
          error_message: "Meeting event was cancelled.",
          updated_by: actor_for(session)
        )
        return
      end

      starts_at = event.starts_at_utc
      if starts_at.present? && starts_at > Time.current + RESCHEDULE_THRESHOLD
        self.class.set(wait_until: starts_at).perform_later(session.id)
        return
      end

      Meetings::BotDispatchService.new(session: session, actor: actor_for(session)).dispatch!
    end

    private

    def actor_for(session)
      session.updated_by || session.created_by
    end
  end
end
