module Kalendarium
  module Providers
    class IcsAdapter < BaseAdapter
      def sync!(calendar: nil)
        calendar
        return true if connection.ics_url.present?

        raise "ICS URL missing"
      end
    end
  end
end
