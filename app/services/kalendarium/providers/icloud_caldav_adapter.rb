module Kalendarium
  module Providers
    class IcloudCaldavAdapter < BaseAdapter
      def sync!
        return true if connection.provider_username.present? && connection.provider_password.present?

        raise "iCloud CalDAV credentials are missing"
      end
    end
  end
end
