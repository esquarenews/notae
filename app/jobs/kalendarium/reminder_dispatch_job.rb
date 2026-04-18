module Kalendarium
  class ReminderDispatchJob < ApplicationJob
    queue_as :default

    WINDOW_SECONDS = 120

    def perform(workspace_id = nil)
      scope = KalendariumEvent.includes(:workspace, :kalendarium_calendar, :created_by)
      scope = scope.where(workspace_id: workspace_id) if workspace_id.present?

      now = Time.current
      window_start = now - WINDOW_SECONDS.seconds
      window_end = now + WINDOW_SECONDS.seconds

      scope.find_each do |event|
        next unless event.kalendarium_calendar.enabled?

        Array(event.reminder_offsets_minutes).each do |offset_minutes|
          reminder_at = event.starts_at_utc - offset_minutes.to_i.minutes
          next unless reminder_at.between?(window_start, window_end)

          dispatch_for_event!(event, offset_minutes)
        end
      end
    end

    private

    def dispatch_for_event!(event, offset_minutes)
      memberships = Membership.where(workspace_id: event.workspace_id).includes(:user)
      memberships.each do |membership|
        recipient = membership.user
        key = "#{event.id}:#{offset_minutes}:#{event.starts_at_utc.to_i}"
        existing = Notification.where(
          workspace_id: event.workspace_id,
          recipient_id: recipient.id,
          notification_type: "calendar_reminder"
        ).where("metadata ->> 'reminder_key' = ?", key).exists?
        next if existing

        notification = Notification.create!(
          workspace_id: event.workspace_id,
          actor_id: event.updated_by_id,
          recipient_id: recipient.id,
          notification_type: "calendar_reminder",
          notifiable: event,
          metadata: {
            reminder_key: key,
            kalendarium_event_id: event.id,
            reminder_offset_minutes: offset_minutes,
            starts_at_utc: event.starts_at_utc.iso8601
          }
        )

        if recipient.email_notify_activity_for?(event.workspace, membership: membership) && (recipient.email_notify_always_send? || !recipient.open_links_in_desktop_app?)
          NotificationMailer.with(notification: notification, mailer_user: event.updated_by).calendar_reminder_notification.deliver_later
        end
      end
    end
  end
end
