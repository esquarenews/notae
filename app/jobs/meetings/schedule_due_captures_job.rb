module Meetings
  class ScheduleDueCapturesJob < ApplicationJob
    queue_as :default

    WINDOW_AHEAD = 0.minutes
    WINDOW_BEHIND = 5.minutes
    AUTO_STOP_GRACE = 2.minutes

    def perform
      stop_ended_online_sessions
      dispatch_due_scheduled_sessions

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
        next unless session.status == "scheduled"

        Meetings::BotDispatchService.new(session: session, actor: actor).dispatch!
      rescue StandardError => error
        Rails.logger.warn("Meetings due-capture scheduling failed for kalendarium_event=#{event.id}: #{error.class}: #{error.message}")
      end
    end

    private

    def stop_ended_online_sessions
      ended_online_sessions.find_each do |session|
        actor = session.updated_by || session.created_by
        reason = "Meeting ended; capture stopped automatically."

        session.meeting_bot_runs.active.find_each do |run|
          run.update!(
            status: "failed",
            finished_at: Time.current,
            error_message: reason
          )
        end

        if session.capture_files.attached?
          session.update!(
            status: "uploading",
            ended_at: Time.current,
            error_message: nil,
            updated_by: actor
          )
          Meetings::ProcessSessionJob.perform_later(session.id)
        else
          session.update!(
            status: "cancelled",
            ended_at: Time.current,
            error_message: reason,
            updated_by: actor
          )
        end
      rescue StandardError => error
        Rails.logger.warn("Meetings auto-stop failed for meeting_session=#{session.id}: #{error.class}: #{error.message}")
      end
    end

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

    def ended_online_sessions
      cutoff = Time.current - AUTO_STOP_GRACE
      MeetingSession
        .joins(:kalendarium_event)
        .where(capture_mode: "online_bot", status: %w[joining recording])
        .where("kalendarium_events.ends_at_utc <= ?", cutoff)
        .where.not(kalendarium_events: { status: "cancelled" })
        .includes(:kalendarium_event, :created_by, :updated_by, :meeting_bot_runs)
    end

    def dispatch_due_scheduled_sessions
      due_scheduled_sessions.find_each do |session|
        actor = session.updated_by || session.created_by
        next if actor.blank?

        Meetings::BotDispatchService.new(session: session, actor: actor).dispatch!
      rescue StandardError => error
        Rails.logger.warn("Meetings due-session dispatch failed for meeting_session=#{session.id}: #{error.class}: #{error.message}")
      end
    end

    def due_scheduled_sessions
      from = Time.current - WINDOW_BEHIND
      to = Time.current + WINDOW_AHEAD

      MeetingSession
        .joins(:kalendarium_event)
        .where(capture_mode: "online_bot", status: "scheduled")
        .where(kalendarium_events: { starts_at_utc: from..to })
        .where.not(kalendarium_events: { status: "cancelled" })
        .includes(:workspace, :kalendarium_event, :created_by, :updated_by)
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
