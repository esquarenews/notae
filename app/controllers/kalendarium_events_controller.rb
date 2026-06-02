class KalendariumEventsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_event, only: %i[update destroy]

  def create
    project_id = effective_event_project_id
    project = find_event_project(project_id)
    if project_id.present? && project.blank?
      skip_authorization
      redirect_to kalendarium_redirect_path,
                  alert: "Selected project could not be found."
      return
    end
    calendar = resolve_event_calendar(project: project, selected_calendar_id: event_params[:kalendarium_calendar_id])
    if calendar.blank?
      skip_authorization
      redirect_to kalendarium_redirect_path,
                  alert: "Select a calendar for this event."
      return
    end
    all_day = ActiveModel::Type::Boolean.new.cast(event_params[:all_day]) || false
    starts_at_utc = parse_local_time(event_params[:starts_at_local])
    ends_at_utc = parse_local_time(event_params[:ends_at_local])

    if starts_at_utc.blank? || ends_at_utc.blank?
      skip_authorization
      redirect_to kalendarium_redirect_path,
                  alert: "Start and end times must be valid."
      return
    end

    starts_at_utc, ends_at_utc = normalize_all_day_times(starts_at_utc: starts_at_utc, ends_at_utc: ends_at_utc) if all_day
    if ends_at_utc <= Time.current
      skip_authorization
      redirect_to kalendarium_redirect_path,
                  alert: "End time must be in the future."
      return
    end

    @event = KalendariumEvent.new(
      event_params.except(:starts_at_local, :ends_at_local, :linked_page_action, :all_day, :kalendarium_project_id, :meeting_capture_enabled).merge(
        workspace: @workspace,
        kalendarium_calendar: calendar,
        kalendarium_project: project,
        created_by: current_user,
        updated_by: current_user,
        starts_at_utc: starts_at_utc,
        ends_at_utc: ends_at_utc,
        all_day: all_day,
        meeting_capture_enabled: event_params.key?(:meeting_capture_enabled) ? ActiveModel::Type::Boolean.new.cast(event_params[:meeting_capture_enabled]) : false,
        reminder_offsets_minutes: normalize_offsets(event_params[:reminder_offsets_minutes])
      )
    )
    apply_linked_nota_action!(@event, event_params[:linked_page_action])
    authorize @event

    if @event.save
      sync_warning = sync_event_to_provider(@event)
      redirect_to kalendarium_redirect_path,
                  flash: event_success_flash("Event created.", sync_warning)
    else
      redirect_to kalendarium_redirect_path, alert: @event.errors.full_messages.to_sentence
    end
  end

  def update
    authorize @event

    project = if event_params.key?(:kalendarium_project_id)
      find_event_project(effective_event_project_id)
    else
      @event.kalendarium_project
    end
    project_id = effective_event_project_id
    if event_params.key?(:kalendarium_project_id) && project_id.present? && project.blank?
      skip_authorization
      redirect_to kalendarium_redirect_path,
                  alert: "Selected project could not be found."
      return
    end

    all_day = if event_params.key?(:all_day)
      ActiveModel::Type::Boolean.new.cast(event_params[:all_day]) || false
    else
      @event.all_day
    end
    @event.assign_attributes(
      event_params.except(:starts_at_local, :ends_at_local, :linked_page_action, :kalendarium_calendar_id, :kalendarium_project_id, :all_day, :meeting_capture_enabled).merge(
        kalendarium_project: project,
        updated_by: current_user,
        all_day: all_day,
        meeting_capture_enabled: event_params.key?(:meeting_capture_enabled) ? ActiveModel::Type::Boolean.new.cast(event_params[:meeting_capture_enabled]) : @event.meeting_capture_enabled,
        reminder_offsets_minutes: normalize_offsets(event_params[:reminder_offsets_minutes])
      )
    )
    if event_params[:starts_at_local].present?
      starts_at_utc = parse_local_time(event_params[:starts_at_local])
      if starts_at_utc.blank?
        skip_authorization
        redirect_to kalendarium_redirect_path,
                    alert: "Start time must be valid."
        return
      end
      @event.starts_at_utc = starts_at_utc
    end
    if event_params[:ends_at_local].present?
      ends_at_utc = parse_local_time(event_params[:ends_at_local])
      if ends_at_utc.blank?
        skip_authorization
        redirect_to kalendarium_redirect_path,
                    alert: "End time must be valid."
        return
      end
      @event.ends_at_utc = ends_at_utc
    end
    if project.present?
      @event.kalendarium_calendar = ensure_project_calendar!(project)
    elsif event_params[:kalendarium_calendar_id].present?
      @event.kalendarium_calendar = policy_scope(KalendariumCalendar).for_workspace(@workspace).find(event_params[:kalendarium_calendar_id])
    end
    if all_day
      @event.starts_at_utc, @event.ends_at_utc = normalize_all_day_times(starts_at_utc: @event.starts_at_utc, ends_at_utc: @event.ends_at_utc)
    end
    apply_linked_nota_action!(@event, event_params[:linked_page_action])

    if @event.save
      sync_warning = sync_event_to_provider(@event)
      redirect_to kalendarium_redirect_path,
                  flash: event_success_flash("Event updated.", sync_warning)
    else
      redirect_to kalendarium_redirect_path, alert: @event.errors.full_messages.to_sentence
    end
  end

  def destroy
    authorize @event

    events_to_destroy = destroy_recurring_series? ? recurring_series_events_for(@event) : [ @event ]
    events_to_destroy.each do |event|
      delete_warning = delete_event_from_provider(event)
      if delete_warning.present?
        redirect_to kalendarium_redirect_path, alert: delete_warning
        return
      end
    end

    KalendariumEvent.where(id: events_to_destroy.map(&:id)).destroy_all
    redirect_to kalendarium_redirect_path, notice: destroy_recurring_series? ? "Recurring events deleted." : "Event deleted."
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
      :meeting_capture_enabled,
      :linked_page_id,
      :linked_db_row_id,
      :linked_page_action,
      reminder_offsets_minutes: []
    )
  end

  def parse_local_time(value)
    return nil if value.blank?

    parsed = user_time_zone.parse(value.to_s)
    raise ArgumentError, "Invalid date/time" if parsed.blank?

    parsed.utc
  rescue ArgumentError, TypeError
    nil
  end

  def normalize_offsets(values)
    Array(values).map(&:to_i).select { |offset| offset >= 0 }.uniq.sort
  end

  def normalize_all_day_times(starts_at_utc:, ends_at_utc:)
    starts_local = starts_at_utc.in_time_zone(user_time_zone)
    ends_local = ends_at_utc.in_time_zone(user_time_zone)
    [ starts_local.beginning_of_day.utc, ends_local.end_of_day.utc ]
  end

  def user_time_zone
    ActiveSupport::TimeZone[current_user.time_zone] || Time.zone
  end

  def kalendarium_redirect_path
    redirect_params = {
      workspace_slug: @workspace.slug,
      view: params[:view],
      date: params[:date]
    }
    redirect_params[:project_id] = params[:project_id].presence if params[:project_id].present?
    redirect_params[:project_scope_id] = params[:project_scope_id].presence if params[:project_scope_id].present?
    calendar_ids = Array(params[:calendar_ids]).map(&:to_s).reject(&:blank?)
    redirect_params[:calendar_ids] = calendar_ids if calendar_ids.any?
    time_zones = Array(params[:tz]).map(&:to_s).reject(&:blank?)
    redirect_params[:tz] = time_zones if time_zones.any?
    redirect_params[:year_daily_events] = "1" if ActiveModel::Type::Boolean.new.cast(params[:year_daily_events])
    redirect_params[:window_start] = params[:window_start].presence if params[:window_start].present?
    redirect_params[:embedded] = "1" if params[:embedded].to_s == "1"
    redirect_params[:widget] = "1" if params[:widget].to_s == "1"
    redirect_params[:task_row_id] = params[:task_row_id].presence if params[:task_row_id].present?
    kalendarium_path(redirect_params)
  end

  def find_event_project(project_id)
    return nil if project_id.blank?

    policy_scope(KalendariumProject).for_workspace(@workspace).find_by(id: project_id)
  end

  def effective_event_project_id
    event_project_id = event_params[:kalendarium_project_id].to_s.presence
    return event_project_id if event_project_id.present?

    params[:project_scope_id].to_s.presence
  end

  def destroy_recurring_series?
    params[:delete_scope].to_s == "series"
  end

  def recurring_series_events_for(event)
    scope = policy_scope(KalendariumEvent).for_workspace(@workspace).where(kalendarium_calendar_id: event.kalendarium_calendar_id)
    google_series_id = event.metadata_json.to_h["recurring_event_id"].to_s.presence
    return scope.where("metadata_json ->> 'recurring_event_id' = ?", google_series_id).to_a if google_series_id.present?

    if event.uid.present? && event.remote_event_id.to_s.include?("::")
      uid_matches = scope.where(uid: event.uid).to_a
      return uid_matches if uid_matches.many?
    end

    [ event ]
  end

  def resolve_event_calendar(project:, selected_calendar_id:)
    return ensure_project_calendar!(project) if project.present?
    return nil if selected_calendar_id.blank?

    policy_scope(KalendariumCalendar).for_workspace(@workspace).find(selected_calendar_id)
  end

  def ensure_project_calendar!(project)
    return project.kalendarium_calendar if project.kalendarium_calendar.present?

    calendar = KalendariumCalendar.create!(
      workspace: @workspace,
      created_by: current_user,
      name: project.name,
      color_hex: project.color_hex,
      source_kind: "project",
      enabled: true
    )
    project.update!(kalendarium_calendar: calendar)
    calendar
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

  def event_success_flash(success_message, sync_warning)
    return { notice: success_message } if sync_warning.blank?

    {
      notice: success_message,
      alert: sync_warning
    }
  end

  def sync_event_to_provider(event)
    return nil if event.kalendarium_calendar.kalendarium_connection.blank?

    Kalendarium::ProviderEventSyncService.new(event: event).upsert_remote!
    clear_pending_sync_marker!(event)
    nil
  rescue StandardError => error
    mark_pending_sync!(event, error: error)
    "Event saved locally, but remote sync failed: #{error.message}"
  end

  def delete_event_from_provider(event)
    return nil if event.kalendarium_calendar.kalendarium_connection.blank?

    Kalendarium::ProviderEventSyncService.new(event: event).delete_remote!
    nil
  rescue StandardError => error
    "Could not delete remote event: #{error.message}. Local event was not deleted."
  end

  def mark_pending_sync!(event, error:)
    metadata = event.metadata_json.to_h
    metadata["pending_remote_sync"] = true
    metadata["pending_remote_sync_error"] = error.message.to_s.truncate(300)
    event.update_columns(metadata_json: metadata, updated_at: Time.current)
  end

  def clear_pending_sync_marker!(event)
    metadata = event.metadata_json.to_h
    removed_pending = metadata.delete("pending_remote_sync")
    removed_error = metadata.delete("pending_remote_sync_error")
    return unless removed_pending || removed_error

    event.update_columns(metadata_json: metadata, updated_at: Time.current)
  end
end
