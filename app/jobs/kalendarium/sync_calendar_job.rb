module Kalendarium
  class SyncCalendarJob < ApplicationJob
    queue_as :default

    def perform(calendar_id)
      calendar = KalendariumCalendar.find_by(id: calendar_id)
      return if calendar.blank?

      connection = calendar.kalendarium_connection
      return if connection.blank? || !connection.enabled?

      Kalendarium::ConnectionSyncService.new(connection: connection, calendar: calendar).call
    end
  end
end
