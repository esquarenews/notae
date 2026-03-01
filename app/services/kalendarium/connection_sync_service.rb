module Kalendarium
  class ConnectionSyncService
    def initialize(connection:, calendar: nil)
      @connection = connection
      @calendar = calendar
    end

    def call
      adapter.sync!(calendar: calendar)
      connection.update!(status: "connected", last_synced_at: Time.current, last_error: nil)
    rescue StandardError => error
      connection.update!(status: "sync_error", last_error: error.message)
      raise
    end

    private

    attr_reader :connection, :calendar

    def adapter
      @adapter ||= case connection.provider
      when "google"
        Kalendarium::Providers::GoogleAdapter.new(connection: connection)
      when "icloud_caldav"
        Kalendarium::Providers::IcloudCaldavAdapter.new(connection: connection)
      when "ics"
        Kalendarium::Providers::IcsAdapter.new(connection: connection)
      else
        Kalendarium::Providers::BaseAdapter.new(connection: connection)
      end
    end
  end
end
