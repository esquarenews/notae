class WorkspaceNotificationBarPresenter
  EVENT_LOOKAHEAD = 15.minutes
  EVENT_GRACE_PERIOD = 5.minutes
  RECENT_ACTIVITY_WINDOW = 1.hour
  AI_NOTIFICATION_TYPES = [
    Notification::TYPE_AGENT_ACTION_APPROVAL_REQUESTED,
    Notification::TYPE_AGENT_ACTION_CHANGES_REQUESTED,
    Notification::TYPE_AGENT_ACTION_RESUBMITTED,
    Notification::TYPE_AGENT_ACTION_APPROVED,
    Notification::TYPE_AGENT_ACTION_REJECTED,
    Notification::TYPE_WORKFLOW_FAILED,
    Notification::TYPE_KNOWLEDGE_SUGGESTION_READY
  ].freeze

  attr_reader :workspace, :user, :reference_time

  def initialize(workspace:, user:, reference_time: Time.zone.now)
    @workspace = workspace
    @user = user
    @reference_time = reference_time
  end

  def render?
    return false if workspace.blank? || workspace.slug.blank? || mode == Workspace::SHELL_STATUS_BAR_MODE_OFF

    show_clock? || has_alerts?
  end

  def show_clock?
    Workspace::SHELL_STATUS_BAR_MODES_WITH_CLOCK.include?(mode)
  end

  def show_alerts?
    Workspace::SHELL_STATUS_BAR_MODES_WITH_ALERTS.include?(mode)
  end

  def mode
    workspace&.display_shell_status_bar_mode || Workspace::DEFAULT_SHELL_STATUS_BAR_MODE
  end

  def time_zone_name
    resolved_time_zone.tzinfo.name
  end

  def initial_clock_label
    local_time = reference_time.in_time_zone(resolved_time_zone)
    "#{local_time.strftime('%a %-d %b')} · #{local_time.strftime('%-l:%M %p').strip}"
  end

  def calendar_widget_date
    reference_time.in_time_zone(resolved_time_zone).to_date.iso8601
  end

  def event_alert
    return unless show_alerts?
    return unless data_source_available?("kalendarium_events")

    @event_alert ||= workspace
      .kalendarium_events
      .where.not(status: "cancelled")
      .where(starts_at_utc: (reference_time - EVENT_GRACE_PERIOD)..(reference_time + EVENT_LOOKAHEAD))
      .select(:id, :title, :starts_at_utc)
      .order(:starts_at_utc)
      .first
  end

  def event_timing_label
    event = event_alert
    return "" if event.blank?

    seconds_until_start = event.starts_at_utc - reference_time
    return "Starting now" if seconds_until_start.abs < 60

    minutes = (seconds_until_start.abs / 60.0).ceil
    seconds_until_start.positive? ? "Starts in #{minutes} min" : "Started #{minutes} min ago"
  end

  def event_alert_key
    event = event_alert
    return "" if event.blank?

    "event:#{event.id}:#{event.starts_at_utc.to_i}"
  end

  def recent_email_count
    return 0 unless show_alerts?
    return 0 unless data_source_available?("epistularium_messages")

    @recent_email_count ||= recent_email_scope.count
  end

  def recent_email_present?
    recent_email_count.positive?
  end

  def recent_email_headline
    return "" unless recent_email_present?

    recent_email_count == 1 ? "1 email just came in" : "#{recent_email_count} emails came in recently"
  end

  def recent_email_detail
    latest_message = recent_email_latest_message
    return "" if latest_message.blank?

    sender = [ latest_message.from_name.to_s.strip.presence, latest_message.from_email.to_s.strip.presence ].compact.join(" ").strip.presence
    subject = latest_message.display_subject
    [ sender.presence, subject.presence ].compact.join(" · ")
  end

  def recent_email_alert_key
    latest_message = recent_email_latest_message
    return "" if latest_message.blank?

    "mail:#{latest_message.id}:#{recent_email_count}"
  end

  def recent_ai_update_count
    return 0 unless show_alerts?
    return 0 unless data_source_available?("notifications")
    return 0 if user.blank?

    @recent_ai_update_count ||= recent_ai_update_scope.count
  end

  def recent_ai_update_present?
    recent_ai_update_count.positive?
  end

  def recent_ai_update_headline
    return "" unless recent_ai_update_present?

    payload = recent_ai_update_payload
    if recent_ai_update_count == 1
      payload[:title].to_s.presence || "New AI update"
    else
      "#{recent_ai_update_count} AI updates"
    end
  end

  def recent_ai_update_detail
    return "" unless recent_ai_update_present?

    payload = recent_ai_update_payload
    if recent_ai_update_count == 1
      payload[:body].to_s.presence || "Review the latest AI activity."
    else
      [ payload[:title].to_s.presence, payload[:body].to_s.presence ].compact.join(" · ").presence || "Recent AI activity needs review."
    end
  end

  def recent_ai_update_path
    latest_notification = recent_ai_update_latest_notification
    return "" if latest_notification.blank?

    Notifications::DestinationResolver.new(notification: latest_notification).call.to_s
  end

  def recent_ai_update_alert_key
    latest_notification = recent_ai_update_latest_notification
    return "" if latest_notification.blank?

    "ai:#{latest_notification.id}:#{recent_ai_update_count}"
  end

  def recent_update_count
    return 0 unless show_alerts?
    return 0 unless data_source_available?("notifications")
    return 0 if user.blank?

    @recent_update_count ||= recent_update_scope.count
  end

  def recent_update_present?
    recent_update_count.positive?
  end

  def recent_update_headline
    return "" unless recent_update_present?

    recent_update_count == 1 ? "1 new workspace update" : "#{recent_update_count} new workspace updates"
  end

  def recent_update_detail
    latest_notification = recent_update_latest_notification
    return "" if latest_notification.blank?

    return "New mention or comment" if latest_notification.notification_type == Notification::TYPE_MENTION
    return "Calendar reminder" if latest_notification.notification_type == Notification::TYPE_CALENDAR_REMINDER

    "Arrived in the last hour"
  end

  def recent_update_alert_key
    latest_notification = recent_update_latest_notification
    return "" if latest_notification.blank?

    "update:#{latest_notification.id}:#{recent_update_count}"
  end

  def has_alerts?
    event_alert.present? || recent_ai_update_present? || recent_email_present? || recent_update_present?
  end

  private

  def resolved_time_zone
    @resolved_time_zone ||= ActiveSupport::TimeZone[user&.time_zone.presence] || Time.zone || ActiveSupport::TimeZone["UTC"]
  end

  def data_source_available?(name)
    ActiveRecord::Base.connection.data_source_exists?(name)
  rescue ActiveRecord::StatementInvalid => error
    return false if optional_schema_error?(error)

    raise
  end

  def optional_schema_error?(error)
    optional_schema_error_message?(error.message) || optional_schema_error_message?(error.cause&.message)
  end

  def optional_schema_error_message?(message)
    text = message.to_s
    text.include?("PG::UndefinedTable") ||
      text.include?("PG::UndefinedColumn") ||
      text.include?("no such table") ||
      text.include?("no such column") ||
      (text.include?("relation") && text.include?("does not exist"))
  end

  def recent_email_latest_message
    return nil unless recent_email_present?

    @recent_email_latest_message ||= recent_email_scope
      .select(:id, :subject, :from_name, :from_email, :received_at, :created_at)
      .order(Arel.sql("COALESCE(epistularium_messages.received_at, epistularium_messages.created_at) DESC"))
      .first
  end

  def recent_update_latest_notification
    return nil unless recent_update_present?

    @recent_update_latest_notification ||= recent_update_scope
      .select(:id, :notification_type, :created_at)
      .order(created_at: :desc)
      .first
  end

  def recent_ai_update_latest_notification
    return nil unless recent_ai_update_present?

    @recent_ai_update_latest_notification ||= recent_ai_update_scope
      .includes(:workspace, :recipient, :actor, :notifiable)
      .recent_first
      .first
  end

  def recent_ai_update_payload
    latest_notification = recent_ai_update_latest_notification
    return {} if latest_notification.blank?

    @recent_ai_update_payloads ||= {}
    @recent_ai_update_payloads[latest_notification.id] ||= WebPush::NotificationPayloadBuilder.new(notification: latest_notification).call
  end

  def recent_email_scope
    workspace
      .epistularium_messages
      .for_mailbox("inbox")
      .where(unread: true)
      .where("COALESCE(epistularium_messages.received_at, epistularium_messages.created_at) >= ?", recent_cutoff)
  end

  def recent_update_scope
    workspace
      .notifications
      .for_recipient(user)
      .unread
      .where.not(notification_type: AI_NOTIFICATION_TYPES)
      .where("notifications.created_at >= ?", recent_cutoff)
  end

  def recent_ai_update_scope
    workspace
      .notifications
      .for_recipient(user)
      .unread
      .where(notification_type: AI_NOTIFICATION_TYPES)
      .where("notifications.created_at >= ?", recent_cutoff)
  end

  def recent_cutoff
    reference_time - RECENT_ACTIVITY_WINDOW
  end
end
