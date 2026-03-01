module Kalendarium
  module Providers
    class GoogleAdapter < BaseAdapter
      def sync!(calendar: nil)
        calendar
        return true if connection.access_token.present?

        raise "Google access token missing"
      end
    end
  end
end
