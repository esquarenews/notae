module Kalendarium
  module Providers
    class BaseAdapter
      def initialize(connection:)
        @connection = connection
      end

      def sync!(calendar: nil)
        # Adapter base intentionally no-op.
        calendar
        true
      end

      private

      attr_reader :connection
    end
  end
end
