module WebPush
  class TestPayloadBuilder
    include Rails.application.routes.url_helpers

    def initialize(user:, workspace:)
      @user = user
      @workspace = workspace
    end

    def call
      {
        title: "Notae test notification",
        body: body,
        url: workspace_notification_settings_path(workspace_slug: workspace.slug),
        tag: "notae-test-push-#{workspace.id}",
        icon: "/icon-192-v5.png",
        badge: "/icon-192-v5.png"
      }
    end

    private

    attr_reader :user, :workspace

    def body
      "Push notifications are working on this device for #{workspace.name}. #{delivered_at_label}"
    end

    def delivered_at_label
      Time.current.in_time_zone(time_zone).strftime("%a %-d %b · %-l:%M %p").strip
    end

    def time_zone
      ActiveSupport::TimeZone[user&.time_zone.presence] || Time.zone || ActiveSupport::TimeZone["UTC"]
    end
  end
end
