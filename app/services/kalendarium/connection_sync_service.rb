module Kalendarium
  class ConnectionSyncService
    def initialize(connection:, calendar: nil, calendars: nil, range_start: nil, range_end: nil, retry_pending_writes: true)
      @connection = connection
      @calendar = calendar
      @calendars = Array(calendars).compact
      @range_start = range_start
      @range_end = range_end
      @retry_pending_writes = retry_pending_writes
    end

    def call
      adapter.sync!(calendar: calendar, calendars: calendars, range_start: range_start, range_end: range_end)
      retry_pending_provider_writes! if retry_pending_writes?
      connection.update!(status: "connected", last_synced_at: Time.current, last_error: nil)
    rescue StandardError => error
      connection.update!(status: "sync_error", last_error: error.message)
      raise
    end

    private

    attr_reader :connection, :calendar, :calendars, :range_start, :range_end

    def retry_pending_writes?
      !!@retry_pending_writes
    end

    def retry_pending_provider_writes!
      return unless retryable_write_provider?

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
        raise "#{provider_name} write sync is paused until this connection is re-authorized. Existing local events are kept and will retry automatically afterward."
      end

      raise "Remote write sync failed for #{failed_syncs.size} event(s): #{failed_syncs.first(3).join(' | ')}"
    end

    def writable_events_scope
      scope = KalendariumEvent
                .joins(:kalendarium_calendar)
                .merge(KalendariumCalendar.user_writable)
                .where(kalendarium_calendars: { kalendarium_connection_id: connection.id })
                .where(status: %w[confirmed tentative])
                .where("kalendarium_events.source_kind = ? OR kalendarium_events.remote_event_id IS NULL OR COALESCE(kalendarium_events.metadata_json ->> 'pending_remote_sync', 'false') = 'true'", "local")

      if calendars.any?
        scope.where(kalendarium_calendar_id: calendars.map(&:id))
      elsif calendar.present?
        scope.where(kalendarium_calendar_id: calendar.id)
      else
        scope
      end
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
        lowered.include?("google calendar write permission is missing") ||
        lowered.include?("token refresh failed") ||
        lowered.include?("caldav authentication failed") ||
        lowered.include?("app-specific password")
    end

    def retryable_write_provider?
      %w[google icloud_caldav].include?(connection.provider)
    end

    def provider_name
      case connection.provider
      when "google"
        "Google"
      when "icloud_caldav"
        "iCloud"
      else
        connection.provider.to_s.titleize
      end
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
