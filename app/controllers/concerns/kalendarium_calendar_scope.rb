module KalendariumCalendarScope
  extend ActiveSupport::Concern

  private

  def selected_provider_calendar_ids_for_workspace
    selectable_calendars = policy_scope(KalendariumCalendar).for_workspace(@workspace).where.not(source_kind: "project").order(:name).to_a
    allowed_ids = selectable_calendars.map { |calendar| calendar.id.to_s }
    requested_ids = Array(params[:calendar_ids]).map(&:to_s).reject(&:blank?)
    filter_applied = params[:calendar_filter_applied].to_s == "1"

    if filter_applied
      return requested_ids & allowed_ids
    end

    selected = requested_ids & allowed_ids
    return selected if selected.any?

    stored_selection = persisted_selected_calendar_ids_for_workspace(allowed_ids:)
    if stored_selection.any?
      return stored_selection
    end

    if stored_calendar_selection_for_workspace?
      if stale_or_legacy_empty_calendar_selection_for_workspace?(allowed_ids:)
        enabled_ids = selectable_calendars.select(&:enabled?).map { |calendar| calendar.id.to_s }
        return enabled_ids.any? ? enabled_ids : allowed_ids
      end

      return []
    end

    enabled_ids = selectable_calendars.select(&:enabled?).map { |calendar| calendar.id.to_s }
    enabled_ids.any? ? enabled_ids : allowed_ids
  end

  def calendar_filter_session_for_workspace
    session[:kalendarium_calendar_selection] ||= {}
  end

  def calendar_filter_workspace_key
    @workspace.id.to_s
  end

  def stored_calendar_selection_for_workspace?
    calendar_filter_session_for_workspace.key?(calendar_filter_workspace_key)
  end

  def persisted_calendar_selection_payload_for_workspace
    raw = calendar_filter_session_for_workspace[calendar_filter_workspace_key]
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

  def persisted_selected_calendar_ids_for_workspace(allowed_ids:)
    payload = persisted_calendar_selection_payload_for_workspace

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

  def stale_or_legacy_empty_calendar_selection_for_workspace?(allowed_ids:)
    return false if allowed_ids.blank?

    payload = persisted_calendar_selection_payload_for_workspace
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
end
