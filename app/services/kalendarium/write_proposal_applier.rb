module Kalendarium
  class WriteProposalApplier
    class Error < StandardError; end

    def initialize(workspace:, actor:, proposal:)
      @workspace = workspace
      @actor = actor
      @proposal = proposal
    end

    def call
      payload = proposal.payload_json.to_h.with_indifferent_access

      case proposal.operation
      when "create"
        create_event(payload)
      when "update"
        update_event(payload)
      when "delete"
        delete_event(payload)
      else
        raise Error, "Unsupported operation"
      end
    end

    private

    attr_reader :workspace, :actor, :proposal

    def create_event(payload)
      calendar = scoped_calendars.find(payload[:kalendarium_calendar_id] || payload[:calendar_id])
      event = KalendariumEvent.new(
        workspace: workspace,
        kalendarium_calendar: calendar,
        kalendarium_project_id: payload[:kalendarium_project_id] || payload[:project_id],
        title: payload[:title].to_s,
        description: payload[:description],
        location: payload[:location],
        starts_at_utc: parse_time(payload[:starts_at_utc] || payload[:starts_at]),
        ends_at_utc: parse_time(payload[:ends_at_utc] || payload[:ends_at]),
        all_day: ActiveModel::Type::Boolean.new.cast(payload[:all_day]) || false,
        rrule: payload[:rrule],
        linked_page_id: payload[:linked_page_id],
        linked_db_row_id: payload[:linked_db_row_id],
        reminder_offsets_minutes: normalize_offsets(payload[:reminder_offsets_minutes]),
        created_by: actor,
        updated_by: actor
      )

      raise Error, event.errors.full_messages.to_sentence unless event.save

      Kalendarium::SyncCalendarJob.perform_later(calendar.id)
      event
    end

    def update_event(payload)
      event = scoped_events.find(payload[:id] || proposal.kalendarium_event_id)
      event.assign_attributes(
        title: payload[:title].presence || event.title,
        description: payload.key?(:description) ? payload[:description] : event.description,
        location: payload.key?(:location) ? payload[:location] : event.location,
        starts_at_utc: payload[:starts_at_utc].present? ? parse_time(payload[:starts_at_utc]) : event.starts_at_utc,
        ends_at_utc: payload[:ends_at_utc].present? ? parse_time(payload[:ends_at_utc]) : event.ends_at_utc,
        all_day: payload.key?(:all_day) ? ActiveModel::Type::Boolean.new.cast(payload[:all_day]) : event.all_day,
        rrule: payload.key?(:rrule) ? payload[:rrule] : event.rrule,
        kalendarium_project_id: payload.key?(:kalendarium_project_id) ? payload[:kalendarium_project_id] : event.kalendarium_project_id,
        linked_page_id: payload.key?(:linked_page_id) ? payload[:linked_page_id] : event.linked_page_id,
        linked_db_row_id: payload.key?(:linked_db_row_id) ? payload[:linked_db_row_id] : event.linked_db_row_id,
        reminder_offsets_minutes: payload.key?(:reminder_offsets_minutes) ? normalize_offsets(payload[:reminder_offsets_minutes]) : event.reminder_offsets_minutes,
        updated_by: actor
      )
      raise Error, event.errors.full_messages.to_sentence unless event.save

      Kalendarium::SyncCalendarJob.perform_later(event.kalendarium_calendar_id)
      event
    end

    def delete_event(payload)
      event = scoped_events.find(payload[:id] || proposal.kalendarium_event_id)
      calendar_id = event.kalendarium_calendar_id
      event.destroy!
      Kalendarium::SyncCalendarJob.perform_later(calendar_id)
      event
    end

    def parse_time(raw)
      parsed = Time.zone.parse(raw.to_s)
      raise Error, "Invalid event time" if parsed.blank?

      parsed.utc
    rescue ArgumentError
      raise Error, "Invalid event time"
    end

    def normalize_offsets(raw)
      Array(raw).map { |value| value.to_i }.select { |value| value >= 0 }.uniq.sort
    end

    def scoped_events
      KalendariumEvent.where(workspace_id: workspace.id)
    end

    def scoped_calendars
      KalendariumCalendar.where(workspace_id: workspace.id)
    end
  end
end
