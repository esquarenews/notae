module Kalendarium
  module Providers
    class BaseAdapter
      def initialize(connection:)
        @connection = connection
      end

      def sync!
        # Adapter base intentionally no-op.
        true
      end

      private

      attr_reader :connection
    end
  end
end
