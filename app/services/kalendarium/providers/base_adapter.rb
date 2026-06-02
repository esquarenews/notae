module Kalendarium
  module Providers
    class BaseAdapter
      def initialize(connection:)
        @connection = connection
      end

      def sync!(calendar: nil, calendars: nil, range_start: nil, range_end: nil)
        # Adapter base intentionally no-op.
        calendar
        calendars
        range_start
        range_end
        true
      end

      private

      attr_reader :connection

      def pending_remote_sync?(event)
        metadata = event.metadata_json.to_h
        ActiveModel::Type::Boolean.new.cast(metadata["pending_remote_sync"]) ||
          ActiveModel::Type::Boolean.new.cast(metadata["pending_provider_calendar_move"])
      end
    end
  end
end
