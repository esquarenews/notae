module Meetings
  class ScheduleDueCapturesJob < ApplicationJob
    queue_as :default

    WINDOW_AHEAD = 10.minutes
    WINDOW_BEHIND = 5.minutes

    def perform
      due_events.find_each do |event|
        actor = event.updated_by || event.created_by
        next if actor.blank?

        session = Meetings::SessionLifecycleService
                    .new(workspace: event.workspace, actor: actor)
                    .create_session!(
                      title: "#{event.title} meeting",
                      capture_mode: "online_bot",
                      provider: provider_for_join_url(event.meeting_join_url),
                      kalendarium_event: event,
                      join_url: event.meeting_join_url,
                      consent_warning_acknowledged: true
                    )

        Meetings::BotDispatchService.new(session: session, actor: actor).dispatch!
      rescue StandardError => error
        Rails.logger.warn("Meetings due-capture scheduling failed for kalendarium_event=#{event.id}: #{error.class}: #{error.message}")
      end
    end

    private

    def due_events
      from = Time.current - WINDOW_BEHIND
      to = Time.current + WINDOW_AHEAD
      KalendariumEvent
        .where(meeting_capture_enabled: true)
        .where(starts_at_utc: from..to)
        .where.not(status: "cancelled")
        .includes(:workspace, :created_by, :updated_by, :meeting_sessions)
        .where.not(metadata_json: {})
    end

    def provider_for_join_url(join_url)
      lowered = join_url.to_s.downcase
      return "google_meet" if lowered.include?("meet.google.")
      return "zoom" if lowered.include?("zoom.us")
      return "teams" if lowered.include?("teams.microsoft.com")

      "google_meet"
    end
  end
end
