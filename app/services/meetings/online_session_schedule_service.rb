module Meetings
  class OnlineSessionScheduleService
    AUTO_STOP_GRACE = 2.minutes

    def initialize(session:)
      @session = session
    end

    def schedule!
      return unless session.capture_mode == "online_bot"
      return if session.kalendarium_event.blank?

      schedule_dispatch!
      schedule_auto_stop!
    end

    private

    attr_reader :session

    def schedule_dispatch!
      starts_at = session.kalendarium_event.starts_at_utc
      return if starts_at.blank?
      return unless session.status == "scheduled"

      Meetings::DispatchScheduledSessionJob.set(wait_until: starts_at).perform_later(session.id)
    end

    def schedule_auto_stop!
      ends_at = session.kalendarium_event.ends_at_utc
      return if ends_at.blank?
      return unless session.status.in?(%w[scheduled joining recording])

      Meetings::AutoStopSessionJob.set(wait_until: ends_at + AUTO_STOP_GRACE).perform_later(session.id)
    end
  end
end
