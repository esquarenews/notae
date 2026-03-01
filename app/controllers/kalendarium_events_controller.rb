class KalendariumEventsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_event, only: %i[update destroy]

  def create
    calendar = policy_scope(KalendariumCalendar).for_workspace(@workspace).find(event_params[:kalendarium_calendar_id])
    starts_at_utc = parse_local_time(event_params[:starts_at_local])
    ends_at_utc = parse_local_time(event_params[:ends_at_local])

    if starts_at_utc.blank? || ends_at_utc.blank?
      skip_authorization
      redirect_to kalendarium_path(workspace_slug: @workspace.slug, view: params[:view], date: params[:date]),
                  alert: "Start and end times must be valid."
      return
    end

    @event = KalendariumEvent.new(
      event_params.except(:starts_at_local, :ends_at_local, :linked_page_action).merge(
        workspace: @workspace,
        kalendarium_calendar: calendar,
        created_by: current_user,
        updated_by: current_user,
        starts_at_utc: starts_at_utc,
        ends_at_utc: ends_at_utc,
        reminder_offsets_minutes: normalize_offsets(event_params[:reminder_offsets_minutes])
      )
    )
    apply_linked_nota_action!(@event, event_params[:linked_page_action])
    authorize @event

    if @event.save
      enqueue_sync_if_external(@event)
      redirect_to kalendarium_path(workspace_slug: @workspace.slug, view: params[:view], date: params[:date]), notice: "Event created."
    else
      redirect_to kalendarium_path(workspace_slug: @workspace.slug, view: params[:view], date: params[:date]), alert: @event.errors.full_messages.to_sentence
    end
  end

  def update
    authorize @event

    @event.assign_attributes(
      event_params.except(:starts_at_local, :ends_at_local, :linked_page_action, :kalendarium_calendar_id).merge(
        updated_by: current_user,
        reminder_offsets_minutes: normalize_offsets(event_params[:reminder_offsets_minutes])
      )
    )
    if event_params[:starts_at_local].present?
      starts_at_utc = parse_local_time(event_params[:starts_at_local])
      if starts_at_utc.blank?
        skip_authorization
        redirect_to kalendarium_path(workspace_slug: @workspace.slug, view: params[:view], date: params[:date]),
                    alert: "Start time must be valid."
        return
      end
      @event.starts_at_utc = starts_at_utc
    end
    if event_params[:ends_at_local].present?
      ends_at_utc = parse_local_time(event_params[:ends_at_local])
      if ends_at_utc.blank?
        skip_authorization
        redirect_to kalendarium_path(workspace_slug: @workspace.slug, view: params[:view], date: params[:date]),
                    alert: "End time must be valid."
        return
      end
      @event.ends_at_utc = ends_at_utc
    end
    if event_params[:kalendarium_calendar_id].present?
      calendar = policy_scope(KalendariumCalendar).for_workspace(@workspace).find(event_params[:kalendarium_calendar_id])
      @event.kalendarium_calendar = calendar
    end
    apply_linked_nota_action!(@event, event_params[:linked_page_action])

    if @event.save
      enqueue_sync_if_external(@event)
      redirect_to kalendarium_path(workspace_slug: @workspace.slug, view: params[:view], date: params[:date]), notice: "Event updated."
    else
      redirect_to kalendarium_path(workspace_slug: @workspace.slug, view: params[:view], date: params[:date]), alert: @event.errors.full_messages.to_sentence
    end
  end

  def destroy
    authorize @event
    calendar = @event.kalendarium_calendar
    @event.destroy!
    Kalendarium::SyncCalendarJob.perform_later(calendar.id) if calendar.kalendarium_connection.present?

    redirect_to kalendarium_path(workspace_slug: @workspace.slug, view: params[:view], date: params[:date]), notice: "Event deleted."
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def set_event
    @event = policy_scope(KalendariumEvent).for_workspace(@workspace).find(params[:id])
  end

  def event_params
    params.require(:kalendarium_event).permit(
      :kalendarium_calendar_id,
      :kalendarium_project_id,
      :title,
      :description,
      :location,
      :starts_at_local,
      :ends_at_local,
      :all_day,
      :rrule,
      :linked_page_id,
      :linked_db_row_id,
      :linked_page_action,
      reminder_offsets_minutes: []
    )
  end

  def parse_local_time(value)
    return nil if value.blank?

    parsed = Time.zone.parse(value.to_s)
    raise ArgumentError, "Invalid date/time" if parsed.blank?

    parsed.utc
  rescue ArgumentError, TypeError
    nil
  end

  def normalize_offsets(values)
    Array(values).map(&:to_i).select { |offset| offset >= 0 }.uniq.sort
  end

  def apply_linked_nota_action!(event, action)
    case action.to_s
    when "create_page"
      page = @workspace.pages.new(title: [ event.title.presence || "Kalendarium event", "notes" ].join(" "), created_by: current_user)
      return unless policy(page).create? && page.save

      event.linked_page = page
    when "clear"
      event.linked_page = nil
    end
  end

  def enqueue_sync_if_external(event)
    return if event.kalendarium_calendar.kalendarium_connection.blank?

    Kalendarium::SyncCalendarJob.perform_later(event.kalendarium_calendar_id)
  end
end
