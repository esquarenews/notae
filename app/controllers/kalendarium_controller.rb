class KalendariumController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace

  VIEW_OPTIONS = %w[day week month year project].freeze

  def show
    authorize @workspace, :show?

    @view = VIEW_OPTIONS.include?(params[:view].to_s) ? params[:view].to_s : "month"
    @selected_date = parse_selected_date
    @week_start_day = week_start_day
    @weekday_labels = ordered_weekday_labels
    @year_weekday_labels = @weekday_labels.map { |label| label.first }
    @projects = policy_scope(KalendariumProject).for_workspace(@workspace).active.order(:name).to_a
    @selected_project_id = params[:project_id].to_s.presence

    @all_calendars = policy_scope(KalendariumCalendar).for_workspace(@workspace).order(:name).to_a
    @selected_calendar_ids = resolve_selected_calendar_ids
    @visible_calendars = @all_calendars.select { |calendar| @selected_calendar_ids.include?(calendar.id.to_s) }

    @time_zone_rail = resolve_time_zone_rail

    range_start, range_end = range_for_view
    @events = policy_scope(KalendariumEvent)
                .for_workspace(@workspace)
                .includes(:kalendarium_calendar, :kalendarium_project, :linked_page)
                .where(kalendarium_calendar_id: @visible_calendars.map(&:id))
                .where.not(status: "cancelled")
                .for_range(range_start, range_end)
                .order(:starts_at_utc)
    if @selected_project_id.present?
      @events = @events.where(kalendarium_project_id: @selected_project_id)
    end
    @events = @events.to_a

    @events_by_day = @events.group_by { |event| event.starts_at_utc.in_time_zone(current_user.time_zone).to_date }
    @week_days = build_week_days
    @month_days = build_month_days
    @year_months = (1..12).map { |month| Date.new(@selected_date.year, month, 1) }
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

  def resolve_selected_calendar_ids
    requested_ids = Array(params[:calendar_ids]).map(&:to_s).reject(&:blank?)
    allowed_ids = @all_calendars.map { |calendar| calendar.id.to_s }

    selected = requested_ids & allowed_ids
    return selected if selected.any?

    enabled = @all_calendars.select(&:enabled?).map { |calendar| calendar.id.to_s }
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
end
