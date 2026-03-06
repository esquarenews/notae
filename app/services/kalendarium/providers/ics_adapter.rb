module Kalendarium
  module Providers
    class IcsAdapter < BaseAdapter
      def sync!(calendar: nil, calendars: nil, range_start: nil, range_end: nil)
        calendar
        calendars
        range_start
        range_end
        return true if connection.ics_url.present?

        raise "ICS URL missing"
      end
    end
  end
end
