module Kalendarium
  module Providers
    class BaseAdapter
      def initialize(connection:)
        @connection = connection
      end

      def sync!(calendar: nil, range_start: nil, range_end: nil)
        # Adapter base intentionally no-op.
        calendar
        range_start
        range_end
        true
      end

      private

      attr_reader :connection
    end
  end
end
