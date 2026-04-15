module Meetings
  class ScheduleDueCapturesJob < ApplicationJob
    queue_as :default

    AUTO_STOP_GRACE = 2.minutes

    def perform
      stop_ended_online_sessions
    end

    private

    def stop_ended_online_sessions
      ended_online_sessions.find_each do |session|
        actor = session.updated_by || session.created_by
        Meetings::StopSessionService.new(
          session: session,
          actor: actor,
          reason: "Meeting ended; capture stopped automatically."
        ).call
      rescue StandardError => error
        Rails.logger.warn("Meetings auto-stop failed for meeting_session=#{session.id}: #{error.class}: #{error.message}")
      end
    end

    def ended_online_sessions
      cutoff = Time.current - AUTO_STOP_GRACE
      MeetingSession
        .joins(:kalendarium_event)
        .where(capture_mode: "online_bot", status: %w[joining recording])
        .where("kalendarium_events.ends_at_utc <= ?", cutoff)
        .where.not(kalendarium_events: { status: "cancelled" })
        .includes(:kalendarium_event, :created_by, :updated_by, :meeting_bot_runs)
    end
  end
end
