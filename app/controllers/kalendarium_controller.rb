class KalendariumController < ApplicationController
  include RequestPerformanceInstrumentation

  before_action :authenticate_user!
  before_action :set_workspace
  track_request_performance_for :show, :refresh

  VIEW_OPTIONS = %w[day next_7_days week month year project].freeze
  WIDGET_VIEW_OPTIONS = %w[day week next_7_days month year].freeze
  TIMELINE_SLOT_MINUTES = 30
  TIMELINE_SLOT_HEIGHT_PX = 28.0
  TIMELINE_DAY_MINUTES = 1_440
  TIMELINE_MIN_DURATION_MINUTES = 30
  ALL_DAY_ROW_HEIGHT_PX = 26
  ALL_DAY_PADDING_PX = 10

  def show
    authorize @workspace, :show?

    @widget_mode = params[:widget].to_s == "1"
    @view = resolve_requested_view(widget_mode: @widget_mode)
    persist_last_calendar_view! unless @widget_mode
    @project_return_view = resolve_project_return_view
    @selected_date = parse_selected_date
    @next_seven_days_start = resolve_next_seven_days_start
    normalize_selected_date_for_view!
    @show_year_daily_events = ActiveModel::Type::Boolean.new.cast(params[:year_daily_events])
    @week_start_day = week_start_day
    @weekday_labels = ordered_weekday_labels
    @year_weekday_labels = @weekday_labels.map { |label| label.first }
    @projects = policy_scope(KalendariumProject).for_workspace(@workspace).active.order(:name).to_a
    @archived_projects = []
    @scoped_project_id = scoped_project_id(@projects)
    @selected_project_id = selected_active_project_id
    @visible_project_ids = resolve_visible_project_ids(@projects)
    @visible_project_id_set = @visible_project_ids.index_with(true)
    @visible_projects = @projects.select { |project| @visible_project_ids.include?(project.id.to_s) }
    active_project_ids = @projects.map(&:id)
    visible_project_calendar_ids = @visible_projects.map(&:kalendarium_calendar_id).compact
    @project_id_by_calendar_id = @projects.each_with_object({}) do |project, index|
      index[project.kalendarium_calendar_id] = project.id if project.kalendarium_calendar_id.present?
    end

    @all_calendars = policy_scope(KalendariumCalendar).for_workspace(@workspace).order(:name).to_a
    @project_calendars = @all_calendars.select { |calendar| calendar.source_kind == "project" && visible_project_calendar_ids.include?(calendar.id) }
    @calendar_filter_calendars = @all_calendars.reject { |calendar| calendar.source_kind == "project" }
    @selected_calendar_ids = resolve_selected_calendar_ids(@calendar_filter_calendars)
    @visible_calendars = @calendar_filter_calendars.select { |calendar| @selected_calendar_ids.include?(calendar.id.to_s) }
    @visible_event_calendars = if @view == "project"
      @project_calendars
    else
      (@visible_calendars + @project_calendars).uniq
    end

    @time_zone_rail = resolve_time_zone_rail
    prepare_task_schedule_state!

    range_start, range_end = range_for_view
    @events = policy_scope(KalendariumEvent)
                .for_workspace(@workspace)
                .includes(:kalendarium_calendar, :kalendarium_project, :linked_page)
                .where(kalendarium_calendar_id: @visible_event_calendars.map(&:id))
                .where.not(status: "cancelled")
                .for_range(range_start, range_end)
                .order(:starts_at_utc)
    if active_project_ids.any?
      @events = if @visible_project_ids.any?
        @events.where(
          "kalendarium_events.kalendarium_project_id IS NULL OR kalendarium_events.kalendarium_project_id IN (?)",
          @visible_project_ids
        )
      else
        @events.where(kalendarium_project_id: nil)
      end
    else
      @events = @events.where(kalendarium_project_id: nil)
    end
    @events = (@events.to_a + cross_workspace_task_blockout_events(range_start:, range_end:)).uniq(&:id).sort_by(&:starts_at_utc)

    prepare_current_view_state!
    @workspace_options = @widget_mode ? [] : policy_scope(Workspace).order(:name).to_a
    @pending_write_proposals = policy_scope(KalendariumWriteProposal)
                                 .for_workspace(@workspace)
                                 .pending
                                 .where(user_id: current_user.id)
                                 .recent_first
                                 .limit(20)
                                 .to_a
    @new_event = KalendariumEvent.new
    @new_project = @widget_mode ? nil : KalendariumProject.new
  end

  def refresh
    authorize @workspace, :show?

    @view = resolve_requested_view(widget_mode: params[:widget].to_s == "1")
    @selected_date = parse_selected_date
    @next_seven_days_start = resolve_next_seven_days_start
    normalize_selected_date_for_view!
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
    calendar_filter_applied = params[:calendar_filter_applied].to_s == "1"
    explicit_empty_scope = calendar_filter_applied && scoped_calendar_ids.empty?
    scoped_calendars_by_connection = refresh_scope_calendars(refreshable_connections).group_by(&:kalendarium_connection_id)
    connections_to_refresh =
      if calendar_filter_applied
        refreshable_connections.select { |connection| scoped_calendars_by_connection[connection.id].present? }
      else
        refreshable_connections
      end

    if explicit_empty_scope
      redirect_to kalendarium_path(kalendarium_redirect_params), alert: "No calendars selected to refresh."
      return
    end

    if connections_to_refresh.empty?
      redirect_to kalendarium_path(kalendarium_redirect_params), alert: "No selected calendars are available to refresh."
      return
    end

    failures = []
    synced_connection_count = 0
    synced_calendar_count = 0

    connections_to_refresh.each do |connection|
      scoped_calendars = scoped_calendars_by_connection.fetch(connection.id, [])
      sync_options = {
        connection: connection,
        range_start: range_start,
        range_end: range_end,
        retry_pending_writes: false
      }

      if scoped_calendars.any?
        Kalendarium::ConnectionSyncService.new(**sync_options.merge(calendars: scoped_calendars)).call
        synced_calendar_count += scoped_calendars.size
      else
        Kalendarium::ConnectionSyncService.new(**sync_options).call
      end

      synced_connection_count += 1
    rescue StandardError => error
      failures << "#{connection.label}: #{error.message}"
    end

    if failures.any?
      if failures.size == connections_to_refresh.size
        redirect_to kalendarium_path(kalendarium_redirect_params), alert: "Refresh failed for all selected connections: #{failures.join(' | ')}"
      else
        completed_count = connections_to_refresh.size - failures.size
        redirect_to kalendarium_path(kalendarium_redirect_params), alert: "Refresh completed for #{helpers.pluralize(completed_count, "connection")} in the current view with errors: #{failures.join(' | ')}"
      end
    elsif synced_calendar_count.positive?
      redirect_to kalendarium_path(kalendarium_redirect_params), notice: "Refresh completed for #{helpers.pluralize(synced_calendar_count, "calendar")} in the current view."
    else
      redirect_to kalendarium_path(kalendarium_redirect_params), notice: "Refresh completed for #{helpers.pluralize(synced_connection_count, "connection")} in the current view."
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
    return @scoped_project_id if @scoped_project_id.present?

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

    stored_selection = persisted_selected_calendar_ids(allowed_ids: allowed_ids)
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
    scoped_id = scoped_project_id(projects)
    return [ scoped_id ] if scoped_id.present?

    payload = persisted_project_visibility_payload

    selected = if stored_project_visibility?
      persisted_visible_project_ids(allowed_ids: allowed_ids)
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
      selected = allowed_ids if !stored_project_visibility? && payload[:ids].empty?
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

      if payload[:legacy_format] && (selected != payload[:ids] || available_ids != allowed_ids)
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
    when "next_7_days"
      [ @next_seven_days_start.beginning_of_day, (@next_seven_days_start + 6.days).end_of_day ]
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
      redirect_params[:project_scope_id] = params[:project_scope_id].to_s.presence if params[:project_scope_id].present?
      redirect_params[:embedded] = "1" if params[:embedded].to_s == "1"
      redirect_params[:widget] = "1" if params[:widget].to_s == "1"
      redirect_params[:task_row_id] = params[:task_row_id].to_s.presence if params[:task_row_id].present?
      redirect_params[:window_start] = params[:window_start].to_s.presence if params[:window_start].present?
    end
  end

  def prepare_task_schedule_state!
    @task_schedule_row = resolve_task_schedule_row
    @task_slot_candidates = []
    @task_slot_candidate_layouts_by_day = {}
    @task_slot_focus_minutes = nil
    @task_slot_error = nil
    return if @task_schedule_row.blank?

    candidate_result = Kalendarium::TaskSchedulingService.new(
      workspace: @workspace,
      row: @task_schedule_row,
      actor: current_user,
      busy_calendar_ids: @visible_event_calendars.map(&:id),
      visible_project_ids: @visible_project_ids
    ).candidate_slots(limit: Kalendarium::TaskSchedulingService::DEFAULT_CANDIDATE_LIMIT)

    unless candidate_result.success?
      @task_slot_error = candidate_result.error
      return
    end

    @task_slot_candidates = candidate_result.slots
    return if @task_slot_candidates.blank?

    first_candidate = @task_slot_candidates.first
    first_candidate_local = first_candidate.starts_at.in_time_zone(current_user.time_zone)
    @task_slot_focus_minutes = (first_candidate_local.hour * 60) + first_candidate_local.min
    first_candidate_date = first_candidate_local.to_date
    if @view == "next_7_days"
      range_end = @next_seven_days_start + 6.days
      if first_candidate_date >= @next_seven_days_start && first_candidate_date <= range_end
        @selected_date = first_candidate_date
      end
    else
      @selected_date = first_candidate_date
    end
    @task_slot_candidate_layouts_by_day = layout_task_slot_candidates_by_day(@task_slot_candidates)
  end

  def cross_workspace_task_blockout_events(range_start:, range_end:)
    policy_scope(KalendariumEvent)
      .where.not(workspace_id: @workspace.id)
      .where(created_by_id: current_user.id)
      .joins(:kalendarium_project)
      .where(kalendarium_projects: { slug: Kalendarium::TasksProjectEnsurer::PROJECT_SLUG })
      .includes(:workspace, :kalendarium_calendar, :kalendarium_project, :linked_page)
      .where.not(status: "cancelled")
      .for_range(range_start, range_end)
      .order(:starts_at_utc)
      .to_a
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

  def prepare_current_view_state!
    @events_by_day = {}
    @year_all_day_events_by_day = {}
    @year_events_by_day = {}
    @year_month_event_counts = {}
    @week_days = []
    @month_days = []
    @year_months = []
    @day_timeline = { all_day_events: [], timed_events: [] }
    @week_timelines = {}
    @day_all_day_offset = 0
    @week_all_day_rows = 0
    @week_all_day_offset = 0
    @project_events_by_project_id = Hash.new { |index, project_id| index[project_id] = [] }

    case @view
    when "day"
      @events_by_day = events_grouped_by_day
      @day_timeline = build_day_timeline(@selected_date)
      @day_all_day_offset = all_day_offset_for_rows(@day_timeline[:all_day_events].size)
    when "week", "next_7_days"
      @events_by_day = events_grouped_by_day
      @week_days = build_week_days
      @week_timelines = @week_days.index_with { |day| build_day_timeline(day) }
      @week_all_day_rows = @week_timelines.values.map { |timeline| timeline[:all_day_events].size }.max.to_i
      @week_all_day_offset = all_day_offset_for_rows(@week_all_day_rows)
    when "year"
      @year_months = (1..12).map { |month| Date.new(@selected_date.year, month, 1) }
      @year_all_day_events_by_day = build_year_events_by_day(@events.select(&:all_day?))
      @year_events_by_day = @show_year_daily_events ? build_year_events_by_day(@events) : @year_all_day_events_by_day
      @year_month_event_counts = build_year_month_event_counts(@events)
    when "project"
      @archived_projects = policy_scope(KalendariumProject)
                           .for_workspace(@workspace)
                           .archived
                           .order(archived_at: :desc, name: :asc)
                           .to_a
      @project_events_by_project_id = build_project_events_by_project_id(@events)
    else
      @events_by_day = events_grouped_by_day
      @month_days = build_month_days
    end
  end

  def build_project_events_by_project_id(events)
    events.each_with_object(Hash.new { |index, project_id| index[project_id] = [] }) do |event, index|
      project_id = event.kalendarium_project_id || @project_id_by_calendar_id[event.kalendarium_calendar_id]
      next if project_id.blank?

      index[project_id] << event
    end
  end

  def events_grouped_by_day
    @events.group_by { |event| event.starts_at_utc.in_time_zone(current_user.time_zone).to_date }
  end

  def build_year_events_by_day(events)
    events.each_with_object(Hash.new { |index, day| index[day] = [] }) do |event, index|
      visible_year_dates_for_event(event).each do |day|
        index[day] << event
      end
    end.transform_values { |day_events| prioritize_year_day_events(day_events) }
  end

  def layout_task_slot_candidates_by_day(slots)
    slots.each_with_object(Hash.new { |index, day| index[day] = [] }) do |slot, index|
      starts_local = slot.starts_at.in_time_zone(current_user.time_zone)
      ends_local = slot.ends_at.in_time_zone(current_user.time_zone)
      start_minutes = (starts_local.hour * 60) + starts_local.min
      end_minutes = (ends_local.hour * 60) + ends_local.min
      duration_minutes = [ end_minutes - start_minutes, TIMELINE_MIN_DURATION_MINUTES ].max

      index[starts_local.to_date] << {
        slot: slot,
        start_minutes: start_minutes,
        end_minutes: end_minutes,
        label: "#{starts_local.strftime("%-I:%M %p")} - #{ends_local.strftime("%-I:%M %p")}",
        start_local_value: starts_local.strftime("%Y-%m-%dT%H:%M"),
        end_local_value: ends_local.strftime("%Y-%m-%dT%H:%M"),
        timeline_style: [
          "top: #{timeline_pixels_for_minutes(start_minutes).round(2)}px",
          "height: #{timeline_pixels_for_minutes(duration_minutes).round(2)}px",
          "left: 0.34rem",
          "width: calc(100% - 0.68rem)"
        ].join("; ")
      }
    end
  end

  def build_year_month_event_counts(events)
    events.each_with_object(Hash.new(0)) do |event, counts|
      visible_year_dates_for_event(event).map(&:month).uniq.each do |month|
        counts[month] += 1
      end
    end
  end

  def visible_year_dates_for_event(event)
    start_of_year = @selected_date.beginning_of_year
    end_of_year = @selected_date.end_of_year

    dates =
      if event.all_day?
        year_label_dates_for_all_day_event(event)
      else
        [ event.starts_at_utc.in_time_zone(current_user.time_zone).to_date ]
      end

    dates.select { |day| day >= start_of_year && day <= end_of_year }
  end

  def year_label_dates_for_all_day_event(event)
    starts_local = event.starts_at_utc.in_time_zone(current_user.time_zone)
    ends_local = event.ends_at_utc.in_time_zone(current_user.time_zone)
    end_date =
      if ends_local == ends_local.beginning_of_day && ends_local > starts_local
        (ends_local - 1.second).to_date
      else
        ends_local.to_date
      end

    start_date = starts_local.to_date
    end_date = start_date if end_date < start_date
    (start_date..end_date).to_a
  end

  def prioritize_year_day_events(events)
    events.sort_by do |event|
      starts_local = event.starts_at_utc.in_time_zone(current_user.time_zone)
      [
        event.all_day? ? 0 : 1,
        starts_local,
        event.id
      ]
    end
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
        start_minutes: segment[:start_minutes],
        end_minutes: segment[:end_minutes],
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

  def resolve_task_schedule_row
    task_row_id = params[:task_row_id].to_s.presence
    return nil if task_row_id.blank?

    row = policy_scope(DbRow).for_workspace(@workspace).active.includes(:database).find_by(id: task_row_id)
    return nil if row.blank?
    return nil unless policy(row).show?

    row
  end

  def build_week_days
    range_start =
      if @view == "next_7_days"
        @next_seven_days_start
      else
        @selected_date.beginning_of_week(week_start_day)
      end

    (0..6).map { |offset| range_start + offset.days }
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

  def resolve_next_seven_days_start
    return @selected_date unless @view == "next_7_days"

    raw = params[:window_start].presence
    return @selected_date if raw.blank?

    Date.parse(raw.to_s)
  rescue ArgumentError
    @selected_date
  end

  def normalize_selected_date_for_view!
    return unless @view == "next_7_days"

    range_end = @next_seven_days_start + 6.days
    return if @selected_date >= @next_seven_days_start && @selected_date <= range_end

    @selected_date = @next_seven_days_start
  end

  def calendar_filter_session
    session[:kalendarium_calendar_selection] ||= {}
  end

  def calendar_filter_workspace_key
    @workspace.id.to_s
  end

  def stored_calendar_selection?
    workspace_calendar_preference_present?("calendar_selection") ||
      calendar_filter_session.key?(calendar_filter_workspace_key)
  end

  def persisted_calendar_selection_payload
    raw = workspace_calendar_preference(
      "calendar_selection",
      fallback: calendar_filter_session[calendar_filter_workspace_key]
    )
    if raw.is_a?(Hash)
      mode = (raw["mode"] || raw[:mode]).to_s
      if %w[all none selected all_except].include?(mode)
        ids = Array(raw["ids"] || raw[:ids]).map(&:to_s).reject(&:blank?).uniq
        { mode: mode, ids: ids, available_ids: [], legacy_format: false }
      else
        selected_ids = Array(raw["selected_ids"] || raw[:selected_ids]).map(&:to_s).reject(&:blank?).uniq
        available_ids = Array(raw["available_ids"] || raw[:available_ids]).map(&:to_s).reject(&:blank?).uniq
        { mode: "selected", ids: selected_ids, available_ids: available_ids, legacy_format: true }
      end
    else
      selected_ids = Array(raw).map(&:to_s).reject(&:blank?).uniq
      { mode: "selected", ids: selected_ids, available_ids: [], legacy_format: true }
    end
  end

  def persisted_selected_calendar_ids(allowed_ids:)
    payload = persisted_calendar_selection_payload

    if payload[:legacy_format]
      return payload[:ids] & allowed_ids
    end

    case payload[:mode]
    when "all"
      allowed_ids
    when "none"
      []
    when "all_except"
      allowed_ids - payload[:ids]
    else
      payload[:ids] & allowed_ids
    end
  end

  def stale_or_legacy_empty_selection?(allowed_ids:)
    return false if allowed_ids.blank?

    payload = persisted_calendar_selection_payload
    selected_ids = payload[:ids]
    available_ids = payload[:available_ids]

    if payload[:legacy_format]
      return true if selected_ids.present? && (selected_ids & allowed_ids).empty?
      return false unless selected_ids.empty?
      return false if available_ids.empty?

      return (available_ids & allowed_ids).empty?
    end

    payload[:mode] == "selected" && selected_ids.present? && (selected_ids & allowed_ids).empty?
  end

  def persist_selected_calendar_ids(ids, available_ids: nil)
    payload = compact_visibility_payload(ids, available_ids)
    if persist_workspace_calendar_preference!("calendar_selection", payload)
      clear_session_workspace_preference!(:kalendarium_calendar_selection, calendar_filter_workspace_key)
    else
      calendar_filter_session[calendar_filter_workspace_key] = payload
    end
  end

  def project_visibility_session
    session[:kalendarium_project_visibility] ||= {}
  end

  def project_visibility_workspace_key
    @workspace.id.to_s
  end

  def stored_project_visibility?
    workspace_calendar_preference_present?("project_visibility") ||
      project_visibility_session.key?(project_visibility_workspace_key)
  end

  def persisted_project_visibility_payload
    raw = workspace_calendar_preference(
      "project_visibility",
      fallback: project_visibility_session[project_visibility_workspace_key]
    )
    if raw.is_a?(Hash)
      mode = (raw["mode"] || raw[:mode]).to_s
      if %w[all none selected all_except].include?(mode)
        {
          mode: mode,
          ids: Array(raw["ids"] || raw[:ids]).map(&:to_s).reject(&:blank?).uniq,
          available_ids: [],
          legacy_format: false
        }
      else
        {
          mode: "selected",
          ids: Array(raw["selected_ids"] || raw[:selected_ids]).map(&:to_s).reject(&:blank?).uniq,
          available_ids: Array(raw["available_ids"] || raw[:available_ids]).map(&:to_s).reject(&:blank?).uniq,
          legacy_format: true
        }
      end
    else
      {
        mode: "selected",
        ids: Array(raw).map(&:to_s).reject(&:blank?).uniq,
        available_ids: [],
        legacy_format: true
      }
    end
  end

  def persist_visible_project_ids(ids, available_ids: nil)
    payload = compact_visibility_payload(ids, available_ids)
    if persist_workspace_calendar_preference!("project_visibility", payload)
      clear_session_workspace_preference!(:kalendarium_project_visibility, project_visibility_workspace_key)
    else
      project_visibility_session[project_visibility_workspace_key] = payload
    end
  end

  def persisted_visible_project_ids(allowed_ids:)
    payload = persisted_project_visibility_payload

    case payload[:mode]
    when "all"
      allowed_ids
    when "none"
      []
    when "all_except"
      allowed_ids - payload[:ids]
    else
      payload[:ids] & allowed_ids
    end
  end

  def compact_visibility_payload(ids, available_ids)
    available = Array(available_ids).map(&:to_s).reject(&:blank?).uniq
    selected = Array(ids).map(&:to_s).reject(&:blank?).uniq
    selected &= available if available.any?

    return { "mode" => "none" } if available.any? && selected.empty?
    return { "mode" => "all" } if available.any? && selected.sort == available.sort

    deselected = available - selected
    if available.any? && deselected.any? && deselected.size < selected.size
      { "mode" => "all_except", "ids" => deselected }
    else
      { "mode" => "selected", "ids" => selected }
    end
  end

  def last_calendar_view_session
    session[:kalendarium_last_calendar_view] ||= {}
  end

  def last_calendar_view_workspace_key
    @workspace.id.to_s
  end

  def persist_last_calendar_view!
    return if @view == "project"

    if persist_workspace_calendar_preference!("last_view", @view)
      clear_session_workspace_preference!(:kalendarium_last_calendar_view, last_calendar_view_workspace_key)
    else
      last_calendar_view_session[last_calendar_view_workspace_key] = @view
    end
  end

  def clear_session_workspace_preference!(session_key, workspace_key)
    workspace_preferences = session[session_key]
    return unless workspace_preferences.respond_to?(:delete)

    workspace_preferences.delete(workspace_key)
    session.delete(session_key) if workspace_preferences.empty?
  end

  def resolve_project_return_view
    requested = params[:return_view].to_s
    return requested if requested.present? && VIEW_OPTIONS.include?(requested) && requested != "project"

    stored = workspace_calendar_preference(
      "last_view",
      fallback: last_calendar_view_session[last_calendar_view_workspace_key]
    ).to_s
    return stored if stored.present? && VIEW_OPTIONS.include?(stored) && stored != "project"

    "week"
  end

  def resolve_requested_view(widget_mode:)
    allowed_views = widget_mode ? WIDGET_VIEW_OPTIONS : VIEW_OPTIONS
    fallback_view = widget_mode ? "day" : "week"
    requested_view = params[:view].to_s
    allowed_views.include?(requested_view) ? requested_view : fallback_view
  end

  def scoped_project_id(projects)
    requested_id = params[:project_scope_id].to_s.presence
    return nil if requested_id.blank?

    allowed_ids = projects.map { |project| project.id.to_s }
    allowed_ids.include?(requested_id) ? requested_id : nil
  end
end
