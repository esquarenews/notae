class WorkspaceNotificationBarPresenter
  EVENT_LOOKAHEAD = 15.minutes
  EVENT_GRACE_PERIOD = 5.minutes

  attr_reader :workspace, :user, :reference_time

  def initialize(workspace:, user:, reference_time: Time.zone.now)
    @workspace = workspace
    @user = user
    @reference_time = reference_time
  end

  def render?
    workspace.present? && mode != Workspace::SHELL_STATUS_BAR_MODE_OFF
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

  def unread_email_count
    return 0 unless show_alerts?
    return 0 unless data_source_available?("epistularium_messages")

    @unread_email_count ||= workspace
      .epistularium_messages
      .for_mailbox("inbox")
      .where(unread: true)
      .count
  end

  def unread_update_count
    return 0 unless show_alerts?
    return 0 unless data_source_available?("notifications")
    return 0 if user.blank?

    @unread_update_count ||= workspace
      .notifications
      .for_recipient(user)
      .unread
      .count
  end

  def has_alerts?
    event_alert.present? || unread_email_count.positive? || unread_update_count.positive?
  end

  def empty_alerts_message
    "No live alerts right now."
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
end
