module Workflows
  module Actions
    class CreateCalendarEvent
      def initialize(workflow_run:)
        @workflow_run = workflow_run
      end

      def call
        calendar = workflow_run.workspace.kalendarium_calendars.find(workflow_run.input_json["kalendarium_calendar_id"])
        raise ArgumentError, "Provider calendars are not allowed for automation" if calendar.source_kind == "provider"

        starts_at = parse_time(workflow_run.input_json["starts_at_local"])
        ends_at = parse_time(workflow_run.input_json["ends_at_local"])
        raise ArgumentError, "Event title is required" if workflow_run.input_json["title"].to_s.strip.blank?
        raise ArgumentError, "Start and end times must be valid" if starts_at.blank? || ends_at.blank?
        raise ArgumentError, "End time must be after start time" if ends_at <= starts_at

        event = workflow_run.workspace.kalendarium_events.create!(
          kalendarium_calendar: calendar,
          title: workflow_run.input_json["title"].to_s.strip,
          description: workflow_run.input_json["description"].to_s,
          location: workflow_run.input_json["location"].to_s,
          starts_at_utc: starts_at.utc,
          ends_at_utc: ends_at.utc,
          created_by: workflow_run.user,
          updated_by: workflow_run.user,
          reminder_offsets_minutes: [],
          meeting_capture_enabled: false
        )

        {
          "target_type" => "KalendariumEvent",
          "target_id" => event.id,
          "title" => event.title,
          "url" => Rails.application.routes.url_helpers.kalendarium_path(
            workspace_slug: workflow_run.workspace.slug,
            view: "day",
            date: event.starts_at_utc.to_date.iso8601,
            anchor: "kalendarium_event_#{event.id}"
          )
        }
      end

      private

      attr_reader :workflow_run

      def parse_time(value)
        zone = ActiveSupport::TimeZone[workflow_run.user.time_zone] || Time.zone
        zone.parse(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end
    end
  end
end
