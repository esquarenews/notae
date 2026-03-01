module Kalendarium
  class SyncConnectionJob < ApplicationJob
    queue_as :default

    def perform(connection_id)
      connection = KalendariumConnection.find_by(id: connection_id)
      return if connection.blank?

      Kalendarium::ConnectionSyncService.new(connection: connection).call
    end
  end
end
