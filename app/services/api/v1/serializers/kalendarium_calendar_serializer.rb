module Api
  module V1
    module Serializers
      class KalendariumCalendarSerializer
        def self.render_collection(calendars)
          calendars.map { |calendar| render(calendar) }
        end

        def self.render(calendar)
          {
            id: calendar.id,
            workspace_id: calendar.workspace_id,
            connection_id: calendar.kalendarium_connection_id,
            name: calendar.name,
            color_hex: calendar.color_hex,
            enabled: calendar.enabled,
            read_only: calendar.read_only,
            writable: calendar.user_writable?,
            time_zone: calendar.time_zone,
            source_kind: calendar.source_kind,
            created_at: calendar.created_at&.iso8601(6),
            updated_at: calendar.updated_at&.iso8601(6)
          }
        end
      end
    end
  end
end
