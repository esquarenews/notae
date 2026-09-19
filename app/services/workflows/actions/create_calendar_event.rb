module Workflows
  module Actions
    class CreateCalendarEvent
      def initialize(workflow_run:)
        @workflow_run = workflow_run
      end

      def call
        calendar = Pundit.policy_scope!(workflow_run.user, KalendariumCalendar)
                         .for_workspace(workflow_run.workspace)
                         .shown_in_kalendarium
                         .find(workflow_run.input_json["kalendarium_calendar_id"])
        raise ArgumentError, "Selected calendar is read-only" unless calendar.user_writable?

        starts_at = parse_time(workflow_run.input_json["starts_at_local"].presence || workflow_run.input_json["starts_at"])
        ends_at = parse_time(workflow_run.input_json["ends_at_local"].presence || workflow_run.input_json["ends_at"])
        raise ArgumentError, "Event title is required" if workflow_run.input_json["title"].to_s.strip.blank?
        raise ArgumentError, "Start and end times must be valid" if starts_at.blank? || ends_at.blank?
        raise ArgumentError, "End time must be after start time" if ends_at <= starts_at

        event = workflow_run.workspace.kalendarium_events.new(
          kalendarium_calendar: calendar,
          title: workflow_run.input_json["title"].to_s.strip,
          description: workflow_run.input_json["description"].to_s,
          location: workflow_run.input_json["location"].to_s,
          starts_at_utc: starts_at.utc,
          ends_at_utc: ends_at.utc,
          all_day: ActiveModel::Type::Boolean.new.cast(workflow_run.input_json["all_day"]) || false,
          rrule: workflow_run.input_json["rrule"].to_s.presence,
          created_by: workflow_run.user,
          updated_by: workflow_run.user,
          reminder_offsets_minutes: Array(workflow_run.input_json["reminder_offsets_minutes"]),
          meeting_capture_enabled: ActiveModel::Type::Boolean.new.cast(workflow_run.input_json["meeting_capture_enabled"]) || false
        )
        Pundit.authorize(workflow_run.user, event, :create?)
        event.save!
        queue_calendar_sync!(calendar)
        event.reload

        {
          "target_type" => "KalendariumEvent",
          "target_id" => event.id,
          "title" => event.title,
          "url" => Rails.application.routes.url_helpers.kalendarium_path(
            workspace_slug: workflow_run.workspace.slug,
            view: "day",
            date: event.starts_at_utc.in_time_zone(event_time_zone).to_date.iso8601,
            anchor: "kalendarium_event_#{event.id}"
          )
        }
      end

      private

      attr_reader :workflow_run

      def parse_time(value)
        event_time_zone.parse(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end

      def event_time_zone
        @event_time_zone ||= ActiveSupport::TimeZone[workflow_run.input_json["time_zone"]] ||
                             ActiveSupport::TimeZone[workflow_run.user.time_zone] ||
                             Time.zone
      end

      def queue_calendar_sync!(calendar)
        return if calendar.kalendarium_connection.blank?

        Kalendarium::SyncCalendarJob.perform_later(calendar.id)
      rescue StandardError => error
        raise unless Queueing::JobEnqueueSafety.queue_unavailable?(error)

        Rails.logger.warn("Kalendarium sync queue unavailable for calendar=#{calendar.id}: #{error.class}: #{error.message}")
      end
    end
  end
end
