class KalendariumController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace

  VIEW_OPTIONS = %w[day week month year project].freeze
  TIMELINE_SLOT_MINUTES = 30
  TIMELINE_SLOT_HEIGHT_PX = 28.0
  TIMELINE_DAY_MINUTES = 1_440
  TIMELINE_MIN_DURATION_MINUTES = 30
  ALL_DAY_ROW_HEIGHT_PX = 26
  ALL_DAY_PADDING_PX = 10

  def show
    authorize @workspace, :show?

    @view = VIEW_OPTIONS.include?(params[:view].to_s) ? params[:view].to_s : "week"
    persist_last_calendar_view!
    @project_return_view = resolve_project_return_view
    @selected_date = parse_selected_date
    @show_year_daily_events = ActiveModel::Type::Boolean.new.cast(params[:year_daily_events])
    @week_start_day = week_start_day
    @weekday_labels = ordered_weekday_labels
    @year_weekday_labels = @weekday_labels.map { |label| label.first }
    @projects = policy_scope(KalendariumProject).for_workspace(@workspace).active.order(:name).to_a
    @archived_projects = policy_scope(KalendariumProject).for_workspace(@workspace).archived.order(archived_at: :desc, name: :asc).to_a
    @selected_project_id = selected_active_project_id
    @visible_project_ids = resolve_visible_project_ids(@projects)
    @visible_projects = @projects.select { |project| @visible_project_ids.include?(project.id.to_s) }
    active_project_ids = @projects.map(&:id)
    active_project_calendar_ids = @projects.map(&:kalendarium_calendar_id).compact

    @all_calendars = policy_scope(KalendariumCalendar).for_workspace(@workspace).order(:name).to_a
    @project_calendars = @all_calendars.select { |calendar| calendar.source_kind == "project" && active_project_calendar_ids.include?(calendar.id) }
    @calendar_filter_calendars = @all_calendars.reject { |calendar| calendar.source_kind == "project" }
    @selected_calendar_ids = resolve_selected_calendar_ids(@calendar_filter_calendars)
    @visible_calendars = @calendar_filter_calendars.select { |calendar| @selected_calendar_ids.include?(calendar.id.to_s) }
    @visible_event_calendars = (@visible_calendars + @project_calendars).uniq

    @time_zone_rail = resolve_time_zone_rail

    range_start, range_end = range_for_view
    @events = policy_scope(KalendariumEvent)
                .for_workspace(@workspace)
                .includes(:kalendarium_calendar, :kalendarium_project, :linked_page)
                .where(kalendarium_calendar_id: @visible_event_calendars.map(&:id))
                .where.not(status: "cancelled")
                .for_range(range_start, range_end)
                .order(:starts_at_utc)
    if active_project_ids.any?
      @events = @events.where(
        "kalendarium_events.kalendarium_project_id IS NULL OR kalendarium_events.kalendarium_project_id IN (?)",
        @visible_project_ids
      )
    else
      @events = @events.where(kalendarium_project_id: nil)
    end
    @events = @events.to_a

    @events_by_day = @events.group_by { |event| event.starts_at_utc.in_time_zone(current_user.time_zone).to_date }
    @workspace_options = policy_scope(Workspace).order(:name).to_a
    @week_days = build_week_days
    @month_days = build_month_days
    @year_months = (1..12).map { |month| Date.new(@selected_date.year, month, 1) }
    @day_timeline = build_day_timeline(@selected_date)
    @week_timelines = @week_days.index_with { |day| build_day_timeline(day) }
    @day_all_day_offset = all_day_offset_for_rows(@day_timeline[:all_day_events].size)
    @week_all_day_rows = @week_timelines.values.map { |timeline| timeline[:all_day_events].size }.max.to_i
    @week_all_day_offset = all_day_offset_for_rows(@week_all_day_rows)
    @pending_write_proposals = policy_scope(KalendariumWriteProposal)
                                 .for_workspace(@workspace)
                                 .pending
                                 .where(user_id: current_user.id)
                                 .recent_first
                                 .limit(20)
                                 .to_a
    @new_event = KalendariumEvent.new
    @new_project = KalendariumProject.new
  end

  def refresh
    authorize @workspace, :show?

    @view = VIEW_OPTIONS.include?(params[:view].to_s) ? params[:view].to_s : "week"
    @selected_date = parse_selected_date
    range_start, range_end = range_for_view

    refreshable_connections = policy_scope(KalendariumConnection)
                                .for_workspace(@workspace)
                                .active
                                .order(:created_at)
                                .to_a
                                .select { |connection| policy(connection).sync? }

    if refreshable_connections.empty?
      redirect_to kalendarium_path(kalendarium_redirect_params), alert: "No connected calendars are available to refresh."
      return
    end

    scoped_calendar_ids = Array(params[:calendar_ids]).map(&:to_s).reject(&:blank?)
    explicit_empty_scope = params[:calendar_filter_applied].to_s == "1" && scoped_calendar_ids.empty?
    scoped_calendars_by_connection = refresh_scope_calendars(refreshable_connections).group_by(&:kalendarium_connection_id)
    failures = []
    queued_failures = []
    synced_connections = []

    refreshable_connections.each do |connection|
      if explicit_empty_scope
        synced_connections << connection
        next
      end

      scoped_calendars = scoped_calendars_by_connection.fetch(connection.id, [])

      if scoped_calendars.any?
        scoped_calendars.each do |calendar|
          Kalendarium::ConnectionSyncService.new(
            connection: connection,
            calendar: calendar,
            range_start: range_start,
            range_end: range_end,
            retry_pending_writes: false
          ).call
        end
      else
        Kalendarium::ConnectionSyncService.new(
          connection: connection,
          range_start: range_start,
          range_end: range_end,
          retry_pending_writes: false
        ).call
      end

      synced_connections << connection
    rescue StandardError => error
      failures << "#{connection.label}: #{error.message}"
    end

    synced_connections.each do |connection|
      Kalendarium::SyncConnectionJob.set(wait: 2.minutes).perform_later(connection.id)
    rescue StandardError => error
      queued_failures << "#{connection.label}: #{error.message}"
    end

    queued_suffix = queued_failures.any? ? " Background full sync queue errors: #{queued_failures.join(' | ')}" : " Full sync queued in background."

    if failures.any?
      if failures.size == refreshable_connections.size
        redirect_to kalendarium_path(kalendarium_redirect_params), alert: "Refresh failed for all connections: #{failures.join(' | ')}"
      else
        completed_count = refreshable_connections.size - failures.size
        redirect_to kalendarium_path(kalendarium_redirect_params), alert: "Refresh completed for #{helpers.pluralize(completed_count, "connection")} with errors: #{failures.join(' | ')}.#{queued_suffix}"
      end
    else
      redirect_to kalendarium_path(kalendarium_redirect_params), notice: "Refresh completed for #{helpers.pluralize(refreshable_connections.size, "connection")} in the current view.#{queued_suffix}"
    end
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def parse_selected_date
    raw = params[:date].presence
    return Date.current if raw.blank?

    Date.parse(raw.to_s)
  rescue ArgumentError
    Date.current
  end

  def selected_active_project_id
    requested_id = params[:project_id].to_s.presence
    return nil if requested_id.blank?

    active_ids = @projects.map { |project| project.id.to_s }
    active_ids.include?(requested_id) ? requested_id : nil
  end

  def resolve_selected_calendar_ids(calendars)
    allowed_ids = calendars.map { |calendar| calendar.id.to_s }
    requested_ids = Array(params[:calendar_ids]).map(&:to_s).reject(&:blank?)
    filter_applied = params[:calendar_filter_applied].to_s == "1"

    if filter_applied
      selected = requested_ids & allowed_ids
      persist_selected_calendar_ids(selected, available_ids: allowed_ids)
      return selected
    end

    selected = requested_ids & allowed_ids
    if selected.any?
      persist_selected_calendar_ids(selected, available_ids: allowed_ids)
      return selected
    end

    stored_selection = persisted_selected_calendar_ids & allowed_ids
    if stored_selection.any?
      persist_selected_calendar_ids(stored_selection, available_ids: allowed_ids)
      return stored_selection
    end

    if stored_calendar_selection?
      if stale_or_legacy_empty_selection?(allowed_ids: allowed_ids)
        enabled_ids = calendars.select(&:enabled?).map { |calendar| calendar.id.to_s }
        fallback_ids = enabled_ids.any? ? enabled_ids : allowed_ids
        persist_selected_calendar_ids(fallback_ids, available_ids: allowed_ids)
        return fallback_ids
      end

      return []
    end

    enabled = calendars.select(&:enabled?).map { |calendar| calendar.id.to_s }
    enabled.any? ? enabled : allowed_ids
  end

  def resolve_time_zone_rail
    requested = Array(params[:tz]).map(&:to_s).reject(&:blank?)
    stored = current_user.calendar_extra_time_zone_list

    [ current_user.time_zone, *(requested.presence || stored) ]
      .compact
      .uniq
      .select { |zone_name| ActiveSupport::TimeZone[zone_name].present? }
  end

  def resolve_visible_project_ids(projects)
    allowed_ids = projects.map { |project| project.id.to_s }
    payload = persisted_project_visibility_payload

    selected = if stored_project_visibility?
      payload[:selected_ids] & allowed_ids
    else
      allowed_ids
    end

    if params[:project_visibility_applied].to_s == "1"
      selected = Array(params[:visible_project_ids]).map(&:to_s).reject(&:blank?) & allowed_ids
      persist_visible_project_ids(selected, available_ids: allowed_ids)
      return selected
    end

    toggle_project_id = params[:toggle_project_id].to_s
    toggle_state = params[:project_visible].to_s
    if toggle_project_id.present? && allowed_ids.include?(toggle_project_id)
      selected = allowed_ids if !stored_project_visibility? && payload[:selected_ids].empty?
      if toggle_state == "1"
        selected |= [ toggle_project_id ]
      else
        selected -= [ toggle_project_id ]
      end
      persist_visible_project_ids(selected, available_ids: allowed_ids)
      return selected
    end

    if stored_project_visibility?
      available_ids = payload[:available_ids]
      selected &= allowed_ids
      if available_ids.present? && (available_ids & allowed_ids).empty?
        selected = allowed_ids
      end

      if selected != payload[:selected_ids] || available_ids != allowed_ids
        persist_visible_project_ids(selected, available_ids: allowed_ids)
      end

      return selected
    end

    persist_visible_project_ids(selected, available_ids: allowed_ids)
    selected
  end

  def range_for_view
    case @view
    when "day"
      [ @selected_date.beginning_of_day, @selected_date.end_of_day ]
    when "week"
      week_start = @selected_date.beginning_of_week(week_start_day)
      [ week_start.beginning_of_day, (week_start + 6.days).end_of_day ]
    when "year"
      [ @selected_date.beginning_of_year.beginning_of_day, @selected_date.end_of_year.end_of_day ]
    when "project"
      [ @selected_date.beginning_of_month.beginning_of_day, (@selected_date + 90.days).end_of_day ]
    else
      month_start = @selected_date.beginning_of_month.beginning_of_week(week_start_day)
      month_end = @selected_date.end_of_month.end_of_week(week_start_day)
      [ month_start.beginning_of_day, month_end.end_of_day ]
    end
  end

  def kalendarium_redirect_params
    {
      workspace_slug: @workspace.slug,
      view: VIEW_OPTIONS.include?(params[:view].to_s) ? params[:view].to_s : "week",
      date: parse_selected_date
    }.tap do |redirect_params|
      project_id = params[:project_id].to_s.presence
      redirect_params[:project_id] = project_id if project_id.present?

      calendar_ids = Array(params[:calendar_ids]).map(&:to_s).reject(&:blank?)
      redirect_params[:calendar_ids] = calendar_ids if calendar_ids.any?

      time_zones = Array(params[:tz]).map(&:to_s).reject(&:blank?)
      redirect_params[:tz] = time_zones if time_zones.any?

      redirect_params[:year_daily_events] = "1" if ActiveModel::Type::Boolean.new.cast(params[:year_daily_events])
    end
  end

  def refresh_scope_calendars(connections)
    connection_ids = connections.map(&:id)
    return [] if connection_ids.empty?

    scope = policy_scope(KalendariumCalendar)
              .for_workspace(@workspace)
              .where(source_kind: "provider", kalendarium_connection_id: connection_ids)
              .order(:name)

    requested_ids = Array(params[:calendar_ids]).map(&:to_s).reject(&:blank?)
    if params[:calendar_filter_applied].to_s == "1"
      return requested_ids.any? ? scope.where(id: requested_ids).to_a : []
    end

    return scope.where(id: requested_ids).to_a if requested_ids.any?

    scope.where(enabled: true).to_a
  end

  def build_day_timeline(day)
    day_events = @events_by_day[day] || []
    all_day_events = day_events.select(&:all_day?)
    timed_events = day_events.reject(&:all_day?)

    {
      all_day_events: all_day_events,
      timed_events: layout_timed_events(timed_events)
    }
  end

  def layout_timed_events(events)
    segments = events.filter_map do |event|
      timed_range = timeline_minutes_for_event(event)
      next if timed_range.blank?

      {
        event: event,
        start_minutes: timed_range[:start_minutes],
        end_minutes: timed_range[:end_minutes]
      }
    end

    return [] if segments.empty?

    overlap_groups(segments.sort_by { |segment| [ segment[:start_minutes], segment[:end_minutes], segment[:event].id ] })
      .flat_map { |group| layout_overlap_group(group) }
  end

  def timeline_minutes_for_event(event)
    starts_local = event.starts_at_utc.in_time_zone(current_user.time_zone)
    ends_local = event.ends_at_utc.in_time_zone(current_user.time_zone)
    start_minutes = (starts_local.hour * 60) + starts_local.min
    end_minutes = (ends_local.hour * 60) + ends_local.min

    if ends_local.to_date > starts_local.to_date || end_minutes < start_minutes
      end_minutes += TIMELINE_DAY_MINUTES
    elsif end_minutes == start_minutes
      end_minutes += TIMELINE_MIN_DURATION_MINUTES
    end

    clamped_start = start_minutes.clamp(0, TIMELINE_DAY_MINUTES - 1)
    clamped_end = [ end_minutes, TIMELINE_DAY_MINUTES ].min
    duration_minutes = [ clamped_end - clamped_start, TIMELINE_MIN_DURATION_MINUTES ].max
    return nil if duration_minutes <= 0

    final_end = [ clamped_start + duration_minutes, TIMELINE_DAY_MINUTES ].min
    return nil if final_end <= clamped_start

    { start_minutes: clamped_start, end_minutes: final_end }
  end

  def overlap_groups(segments)
    groups = []
    current_group = []
    current_group_end = nil

    segments.each do |segment|
      if current_group.any? && segment[:start_minutes] < current_group_end
        current_group << segment
        current_group_end = [ current_group_end, segment[:end_minutes] ].max
      else
        groups << current_group if current_group.any?
        current_group = [ segment ]
        current_group_end = segment[:end_minutes]
      end
    end

    groups << current_group if current_group.any?
    groups
  end

  def layout_overlap_group(group)
    lane_end_minutes = []
    placed_segments = group.map do |segment|
      lane_index = lane_end_minutes.find_index { |lane_end| lane_end <= segment[:start_minutes] }
      lane_index = lane_end_minutes.length if lane_index.nil?
      lane_end_minutes[lane_index] = segment[:end_minutes]
      segment.merge(lane_index: lane_index)
    end

    lane_count = [ lane_end_minutes.length, 1 ].max
    placed_segments.map do |segment|
      width_percent = (100.0 / lane_count).round(4)
      left_percent = (segment[:lane_index] * width_percent).round(4)
      duration_minutes = [ segment[:end_minutes] - segment[:start_minutes], TIMELINE_MIN_DURATION_MINUTES ].max
      top_pixels = timeline_pixels_for_minutes(segment[:start_minutes]).round(2)
      height_pixels = timeline_pixels_for_minutes(duration_minutes).round(2)

      {
        event: segment[:event],
        timeline_style: [
          "top: #{top_pixels}px",
          "height: #{height_pixels}px",
          "left: calc(#{left_percent}% + 0.28rem)",
          "width: calc(#{width_percent}% - 0.36rem)"
        ].join("; ")
      }
    end
  end

  def timeline_pixels_for_minutes(minutes)
    (minutes.to_f / TIMELINE_SLOT_MINUTES) * TIMELINE_SLOT_HEIGHT_PX
  end

  def all_day_offset_for_rows(row_count)
    return 0 if row_count.to_i <= 0

    (row_count.to_i * ALL_DAY_ROW_HEIGHT_PX) + ALL_DAY_PADDING_PX
  end

  def build_week_days
    week_start = @selected_date.beginning_of_week(week_start_day)
    (0..6).map { |offset| week_start + offset.days }
  end

  def build_month_days
    start_date = @selected_date.beginning_of_month.beginning_of_week(week_start_day)
    end_date = @selected_date.end_of_month.end_of_week(week_start_day)
    (start_date..end_date).to_a
  end

  def week_start_day
    current_user.start_week_on_monday? ? :monday : :sunday
  end

  def ordered_weekday_labels
    base_day = Date.current.beginning_of_week(week_start_day)
    (0..6).map { |offset| (base_day + offset.days).strftime("%a") }
  end

  def calendar_filter_session
    session[:kalendarium_calendar_selection] ||= {}
  end

  def calendar_filter_workspace_key
    @workspace.id.to_s
  end

  def stored_calendar_selection?
    calendar_filter_session.key?(calendar_filter_workspace_key)
  end

  def persisted_calendar_selection_payload
    raw = calendar_filter_session[calendar_filter_workspace_key]
    if raw.is_a?(Hash)
      selected_ids = Array(raw["selected_ids"] || raw[:selected_ids]).map(&:to_s).reject(&:blank?).uniq
      available_ids = Array(raw["available_ids"] || raw[:available_ids]).map(&:to_s).reject(&:blank?).uniq
      { selected_ids: selected_ids, available_ids: available_ids, legacy_format: false }
    else
      selected_ids = Array(raw).map(&:to_s).reject(&:blank?).uniq
      { selected_ids: selected_ids, available_ids: [], legacy_format: true }
    end
  end

  def persisted_selected_calendar_ids
    persisted_calendar_selection_payload[:selected_ids]
  end

  def stale_or_legacy_empty_selection?(allowed_ids:)
    return false if allowed_ids.blank?

    payload = persisted_calendar_selection_payload
    selected_ids = payload[:selected_ids]
    available_ids = payload[:available_ids]

    return true if selected_ids.present? && (selected_ids & allowed_ids).empty?
    return false unless selected_ids.empty?
    return true if payload[:legacy_format]
    return false if available_ids.empty?

    (available_ids & allowed_ids).empty?
  end

  def persist_selected_calendar_ids(ids, available_ids: nil)
    calendar_filter_session[calendar_filter_workspace_key] = {
      "selected_ids" => Array(ids).map(&:to_s).reject(&:blank?).uniq,
      "available_ids" => Array(available_ids).map(&:to_s).reject(&:blank?).uniq
    }
  end

  def project_visibility_session
    session[:kalendarium_project_visibility] ||= {}
  end

  def project_visibility_workspace_key
    @workspace.id.to_s
  end

  def stored_project_visibility?
    project_visibility_session.key?(project_visibility_workspace_key)
  end

  def persisted_project_visibility_payload
    raw = project_visibility_session[project_visibility_workspace_key]
    if raw.is_a?(Hash)
      {
        selected_ids: Array(raw["selected_ids"] || raw[:selected_ids]).map(&:to_s).reject(&:blank?).uniq,
        available_ids: Array(raw["available_ids"] || raw[:available_ids]).map(&:to_s).reject(&:blank?).uniq
      }
    else
      {
        selected_ids: Array(raw).map(&:to_s).reject(&:blank?).uniq,
        available_ids: []
      }
    end
  end

  def persist_visible_project_ids(ids, available_ids: nil)
    project_visibility_session[project_visibility_workspace_key] = {
      "selected_ids" => Array(ids).map(&:to_s).reject(&:blank?).uniq,
      "available_ids" => Array(available_ids).map(&:to_s).reject(&:blank?).uniq
    }
  end

  def last_calendar_view_session
    session[:kalendarium_last_calendar_view] ||= {}
  end

  def last_calendar_view_workspace_key
    @workspace.id.to_s
  end

  def persist_last_calendar_view!
    return if @view == "project"

    last_calendar_view_session[last_calendar_view_workspace_key] = @view
  end

  def resolve_project_return_view
    requested = params[:return_view].to_s
    return requested if requested.present? && VIEW_OPTIONS.include?(requested) && requested != "project"

    stored = last_calendar_view_session[last_calendar_view_workspace_key].to_s
    return stored if stored.present? && VIEW_OPTIONS.include?(stored) && stored != "project"

    "week"
  end
end
