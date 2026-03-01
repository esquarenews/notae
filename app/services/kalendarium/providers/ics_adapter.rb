module Kalendarium
  module Providers
    class IcsAdapter < BaseAdapter
      def sync!
        return true if connection.ics_url.present?

        raise "ICS URL missing"
      end
    end
  end
end
