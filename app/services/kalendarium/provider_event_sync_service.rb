module Kalendarium
  class ProviderEventSyncService
    def initialize(event:)
      @event = event
    end

    def upsert_remote!
      return event unless provider_backed_calendar?

      unless provider_adapter.respond_to?(:upsert_remote_event!)
        raise "Provider #{connection.provider} does not support remote event writes yet."
      end

      provider_adapter.upsert_remote_event!(calendar: calendar, event: event)
    end

    def delete_remote!
      return true unless provider_backed_calendar?
      return true if event.remote_event_id.blank?

      unless provider_adapter.respond_to?(:delete_remote_event!)
        raise "Provider #{connection.provider} does not support remote event deletes yet."
      end

      provider_adapter.delete_remote_event!(calendar: calendar, event: event)
    end

    private

    attr_reader :event

    def calendar
      @calendar ||= event.kalendarium_calendar
    end

    def connection
      @connection ||= calendar.kalendarium_connection
    end

    def provider_backed_calendar?
      connection.present?
    end

    def provider_adapter
      @provider_adapter ||= case connection.provider
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
