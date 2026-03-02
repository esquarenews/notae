module Kalendarium
  class ConnectionSyncService
    def initialize(connection:, calendar: nil)
      @connection = connection
      @calendar = calendar
    end

    def call
      adapter.sync!(calendar: calendar)
      retry_pending_provider_writes!
      connection.update!(status: "connected", last_synced_at: Time.current, last_error: nil)
    rescue StandardError => error
      connection.update!(status: "sync_error", last_error: error.message)
      raise
    end

    private

    attr_reader :connection, :calendar

    def retry_pending_provider_writes!
      return unless connection.provider == "google"

      failed_syncs = []
      writable_events_scope.find_each do |event|
        begin
          Kalendarium::ProviderEventSyncService.new(event: event).upsert_remote!
          clear_pending_sync_marker!(event)
        rescue StandardError => error
          mark_pending_sync!(event, error: error)
          failed_syncs << "#{event.title}: #{error.message}"
        end
      end

      return if failed_syncs.empty?

      if failed_syncs.all? { |failure| authentication_failure_message?(failure) }
        raise "Google write sync is paused until this connection is re-authorized. Existing local events are kept and will retry automatically afterward."
      end

      raise "Remote write sync failed for #{failed_syncs.size} event(s): #{failed_syncs.first(3).join(' | ')}"
    end

    def writable_events_scope
      scope = KalendariumEvent
                .joins(:kalendarium_calendar)
                .where(kalendarium_calendars: { kalendarium_connection_id: connection.id, read_only: false })
                .where(status: %w[confirmed tentative])
                .where("kalendarium_events.source_kind = ? OR kalendarium_events.remote_event_id IS NULL OR COALESCE(kalendarium_events.metadata_json ->> 'pending_remote_sync', 'false') = 'true'", "local")

      calendar.present? ? scope.where(kalendarium_calendar_id: calendar.id) : scope
    end

    def mark_pending_sync!(event, error:)
      metadata = event.metadata_json.to_h
      metadata["pending_remote_sync"] = true
      metadata["pending_remote_sync_error"] = error.message.to_s.truncate(300)
      event.update_columns(metadata_json: metadata, updated_at: Time.current)
    end

    def clear_pending_sync_marker!(event)
      metadata = event.metadata_json.to_h
      removed_pending = metadata.delete("pending_remote_sync")
      removed_error = metadata.delete("pending_remote_sync_error")
      return unless removed_pending || removed_error

      event.update_columns(metadata_json: metadata, updated_at: Time.current)
    end

    def authentication_failure_message?(message)
      lowered = message.to_s.downcase
      lowered.include?("google authentication failed") ||
        lowered.include?("reconnect google") ||
        lowered.include?("permission is missing") ||
        lowered.include?("token refresh failed")
    end

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
