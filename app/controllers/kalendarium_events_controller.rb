class KalendariumEventsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_event, only: %i[update destroy]

  def create
    calendar = policy_scope(KalendariumCalendar).for_workspace(@workspace).find(event_params[:kalendarium_calendar_id])
    all_day = ActiveModel::Type::Boolean.new.cast(event_params[:all_day]) || false
    starts_at_utc = parse_local_time(event_params[:starts_at_local])
    ends_at_utc = parse_local_time(event_params[:ends_at_local])

    if starts_at_utc.blank? || ends_at_utc.blank?
      skip_authorization
      redirect_to kalendarium_path(workspace_slug: @workspace.slug, view: params[:view], date: params[:date]),
                  alert: "Start and end times must be valid."
      return
    end

    starts_at_utc, ends_at_utc = normalize_all_day_times(starts_at_utc: starts_at_utc, ends_at_utc: ends_at_utc) if all_day
    if ends_at_utc <= Time.current
      skip_authorization
      redirect_to kalendarium_path(workspace_slug: @workspace.slug, view: params[:view], date: params[:date]),
                  alert: "End time must be in the future."
      return
    end

    @event = KalendariumEvent.new(
      event_params.except(:starts_at_local, :ends_at_local, :linked_page_action, :all_day).merge(
        workspace: @workspace,
        kalendarium_calendar: calendar,
        created_by: current_user,
        updated_by: current_user,
        starts_at_utc: starts_at_utc,
        ends_at_utc: ends_at_utc,
        all_day: all_day,
        reminder_offsets_minutes: normalize_offsets(event_params[:reminder_offsets_minutes])
      )
    )
    apply_linked_nota_action!(@event, event_params[:linked_page_action])
    authorize @event

    if @event.save
      sync_warning = sync_event_to_provider(@event)
      redirect_to kalendarium_path(workspace_slug: @workspace.slug, view: params[:view], date: params[:date]),
                  flash: event_success_flash("Event created.", sync_warning)
    else
      redirect_to kalendarium_path(workspace_slug: @workspace.slug, view: params[:view], date: params[:date]), alert: @event.errors.full_messages.to_sentence
    end
  end

  def update
    authorize @event

    all_day = if event_params.key?(:all_day)
      ActiveModel::Type::Boolean.new.cast(event_params[:all_day]) || false
    else
      @event.all_day
    end
    @event.assign_attributes(
      event_params.except(:starts_at_local, :ends_at_local, :linked_page_action, :kalendarium_calendar_id, :all_day).merge(
        updated_by: current_user,
        all_day: all_day,
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
    if all_day
      @event.starts_at_utc, @event.ends_at_utc = normalize_all_day_times(starts_at_utc: @event.starts_at_utc, ends_at_utc: @event.ends_at_utc)
    end
    apply_linked_nota_action!(@event, event_params[:linked_page_action])

    if @event.save
      sync_warning = sync_event_to_provider(@event)
      redirect_to kalendarium_path(workspace_slug: @workspace.slug, view: params[:view], date: params[:date]),
                  flash: event_success_flash("Event updated.", sync_warning)
    else
      redirect_to kalendarium_path(workspace_slug: @workspace.slug, view: params[:view], date: params[:date]), alert: @event.errors.full_messages.to_sentence
    end
  end

  def destroy
    authorize @event
    delete_warning = delete_event_from_provider(@event)
    if delete_warning.present?
      redirect_to kalendarium_path(workspace_slug: @workspace.slug, view: params[:view], date: params[:date]), alert: delete_warning
      return
    end

    @event.destroy!
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

  def normalize_all_day_times(starts_at_utc:, ends_at_utc:)
    [ starts_at_utc.beginning_of_day, ends_at_utc.end_of_day ]
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
