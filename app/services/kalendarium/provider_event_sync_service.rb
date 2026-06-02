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

      if provider_calendar_move_pending? && provider_adapter.respond_to?(:move_remote_event!)
        provider_adapter.move_remote_event!(from_calendar: previous_calendar, to_calendar: calendar, event: event)
      else
        provider_adapter.upsert_remote_event!(calendar: calendar, event: event)
      end
      clear_provider_calendar_move_marker!
      event
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

    def provider_calendar_move_pending?
      ActiveModel::Type::Boolean.new.cast(event.metadata_json.to_h["pending_provider_calendar_move"]) &&
        previous_calendar.present? &&
        previous_remote_event_id.present?
    end

    def previous_calendar
      @previous_calendar ||= begin
        metadata = event.metadata_json.to_h
        id = metadata["previous_calendar_id"].to_s.presence
        previous = connection.kalendarium_calendars.find_by(id: id) if id.present?
        previous || connection.kalendarium_calendars.find_by(remote_id: metadata["previous_calendar_remote_id"].to_s.presence)
      end
    end

    def previous_remote_event_id
      event.metadata_json.to_h["previous_remote_event_id"].to_s.presence
    end

    def clear_provider_calendar_move_marker!
      metadata = event.metadata_json.to_h
      removed = false
      %w[
        pending_provider_calendar_move
        previous_calendar_id
        previous_calendar_remote_id
        previous_remote_event_id
        previous_remote_href
        previous_remote_etag
      ].each do |key|
        removed ||= metadata.key?(key)
        metadata.delete(key)
      end
      return unless removed

      event.update_columns(metadata_json: metadata, updated_at: Time.current)
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
