module Api
  module V1
    module Serializers
      class KalendariumEventSerializer
        def self.render_collection(events)
          events.map { |event| render(event) }
        end

        def self.render(event)
          {
            id: event.id,
            workspace_id: event.workspace_id,
            calendar_id: event.kalendarium_calendar_id,
            project_id: event.kalendarium_project_id,
            title: event.title,
            description: event.description,
            location: event.location,
            starts_at_utc: event.starts_at_utc&.iso8601(6),
            ends_at_utc: event.ends_at_utc&.iso8601(6),
            all_day: event.all_day,
            rrule: event.rrule,
            status: event.status,
            visibility: event.visibility,
            source_kind: event.source_kind,
            linked_page_id: event.linked_page_id,
            linked_db_row_id: event.linked_db_row_id,
            reminder_offsets_minutes: event.reminder_offsets_minutes,
            created_at: event.created_at&.iso8601(6),
            updated_at: event.updated_at&.iso8601(6)
          }
        end
      end
    end
  end
end
