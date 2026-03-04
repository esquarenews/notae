module Kalendarium
  module Providers
    class IcsAdapter < BaseAdapter
      def sync!(calendar: nil, range_start: nil, range_end: nil)
        calendar
        range_start
        range_end
        return true if connection.ics_url.present?

        raise "ICS URL missing"
      end
    end
  end
end
