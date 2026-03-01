module Kalendarium
  class SyncConnectionJob < ApplicationJob
    queue_as :default

    def perform(connection_id)
      connection = KalendariumConnection.find_by(id: connection_id)
      return if connection.blank?

      Kalendarium::ConnectionSyncService.new(connection: connection).call

      connection.kalendarium_calendars.find_each do |calendar|
        Kalendarium::SyncCalendarJob.perform_later(calendar.id)
      end
    end
  end
end
