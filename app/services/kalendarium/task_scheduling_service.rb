module Kalendarium
  class TaskSchedulingService
    Slot = Struct.new(:starts_at, :ends_at, keyword_init: true) do
      def duration_minutes
        ((ends_at - starts_at) / 60).round
      end
    end

    Result = Struct.new(:event, :error, keyword_init: true) do
      def success?
        error.blank?
      end
    end

    CandidateResult = Struct.new(:slots, :error, keyword_init: true) do
      def success?
        error.blank?
      end
    end

    DEFAULT_DURATION_MINUTES = 20
    SLOT_STEP_MINUTES = 5
    WINDOW_START_HOUR = 8
    WINDOW_END_HOUR = 18
    DEFAULT_LOOKAHEAD_DAYS = 14
    ESTABLISHED_PROPERTY_PATTERN = /\A(date created|created|established|start date)\z/i
    DEADLINE_PROPERTY_PATTERN = /\A(due(?: date)?|deadline|end(?: date)?)\z/i

    def initialize(workspace:, row:, actor:, duration_minutes: DEFAULT_DURATION_MINUTES, tasks_project: nil)
      @workspace = workspace
      @row = row
      @actor = actor
      @duration_minutes = duration_minutes.to_i.positive? ? duration_minutes.to_i : DEFAULT_DURATION_MINUTES
      @tasks_project = tasks_project
    end

    def call
      candidates = candidate_slots(limit: 1)
      return Result.new(error: candidates.error) unless candidates.success?

      slot = candidates.slots.first
      if slot.blank?
        return Result.new(error: unavailable_slot_message)
      end

      event = build_event(starts_at: slot.starts_at, ends_at: slot.ends_at)
      return Result.new(error: tasks_project_error_message) if event.blank?

      Result.new(event:)
    end

    def candidate_slots(limit: 3)
      project = resolved_tasks_project
      return CandidateResult.new(slots: [], error: tasks_project_error_message) if project.blank? || project.kalendarium_calendar.blank?

      lower_bound = earliest_start_time
      upper_bound = latest_end_time(lower_bound)

      if upper_bound <= lower_bound
        return CandidateResult.new(slots: [], error: unavailable_slot_message)
      end

      slots = available_slots(limit:, lower_bound:, upper_bound:)
      if slots.blank?
        return CandidateResult.new(slots: [], error: unavailable_slot_message)
      end

      CandidateResult.new(slots:)
    end

    def build_event(starts_at:, ends_at:, tasks_project: nil)
      project = tasks_project || resolved_tasks_project
      return nil if project.blank? || project.kalendarium_calendar.blank?

      starts_at_local = starts_at.in_time_zone(time_zone)
      ends_at_local = ends_at.in_time_zone(time_zone)

      KalendariumEvent.new(
        workspace: workspace,
        kalendarium_calendar: project.kalendarium_calendar,
        kalendarium_project: project,
        linked_db_row: row,
        title: row.title,
        starts_at_utc: starts_at_local.utc,
        ends_at_utc: ends_at_local.utc,
        created_by: actor,
        updated_by: actor
      )
    end

    private

    attr_reader :workspace, :row, :actor, :duration_minutes, :tasks_project

    def earliest_start_time
      [
        Time.current.in_time_zone(time_zone),
        row.created_at.in_time_zone(time_zone),
        established_date&.in_time_zone(time_zone)&.beginning_of_day
      ].compact.max
    end

    def latest_end_time(lower_bound)
      deadline = deadline_date
      return [ lower_bound + DEFAULT_LOOKAHEAD_DAYS.days, window_end_for(lower_bound.to_date) ].max if deadline.blank?

      deadline_end = deadline.in_time_zone(time_zone).end_of_day
      [ deadline_end, window_end_for(deadline.to_date) ].min
    end

    def available_slots(limit:, lower_bound:, upper_bound:)
      intervals = merged_busy_intervals(lower_bound:, upper_bound:)
      cursor_date = lower_bound.to_date
      slots = []

      while cursor_date <= upper_bound.to_date && slots.size < limit
        window_start = [ lower_bound, window_start_for(cursor_date) ].max
        window_end = [ upper_bound, window_end_for(cursor_date) ].min
        candidate_start = round_up_to_step(window_start)

        while (candidate_start + duration_minutes.minutes) <= window_end && slots.size < limit
          candidate_end = candidate_start + duration_minutes.minutes
          overlapping_interval = intervals.find do |interval|
            interval[:start_at] < candidate_end && interval[:end_at] > candidate_start
          end

          if overlapping_interval.blank?
            slots << Slot.new(starts_at: candidate_start, ends_at: candidate_end)
            candidate_start = round_up_to_step(candidate_end)
            next
          end

          candidate_start = round_up_to_step([ overlapping_interval[:end_at], candidate_start + SLOT_STEP_MINUTES.minutes ].max)
        end

        cursor_date += 1.day
      end

      slots
    end

    def merged_busy_intervals(lower_bound:, upper_bound:)
      busy_intervals = busy_events(lower_bound:, upper_bound:).map do |event|
        {
          start_at: [ event.starts_at_utc.in_time_zone(time_zone), lower_bound ].max,
          end_at: [ event.ends_at_utc.in_time_zone(time_zone), upper_bound ].min
        }
      end.select { |interval| interval[:end_at] > interval[:start_at] }
       .sort_by { |interval| [ interval[:start_at], interval[:end_at] ] }

      busy_intervals.each_with_object([]) do |interval, merged|
        previous = merged.last
        if previous.present? && previous[:end_at] >= interval[:start_at]
          previous[:end_at] = [ previous[:end_at], interval[:end_at] ].max
        else
          merged << interval
        end
      end
    end

    def busy_events(lower_bound:, upper_bound:)
      calendar_ids = workspace.kalendarium_calendars.enabled.pluck(:id)
      return [] if calendar_ids.empty?

      KalendariumEvent
        .for_workspace(workspace)
        .where(kalendarium_calendar_id: calendar_ids)
        .where.not(status: "cancelled")
        .for_range(lower_bound.utc, upper_bound.utc)
        .order(:starts_at_utc)
        .to_a
    end

    def established_date
      date_for_matching_property(ESTABLISHED_PROPERTY_PATTERN)
    end

    def deadline_date
      date_for_matching_property(DEADLINE_PROPERTY_PATTERN)
    end

    def date_for_matching_property(pattern)
      property = ordered_properties.find { |db_property| db_property.date? && db_property.name.to_s.match?(pattern) }
      return nil if property.blank?

      parse_date(row_cells_by_property_id[property.id])
    end

    def ordered_properties
      @ordered_properties ||= row.database.db_properties.order(:position, :created_at).to_a
    end

    def row_cells_by_property_id
      @row_cells_by_property_id ||= row.db_cells.where(db_property_id: ordered_properties.map(&:id)).pluck(:db_property_id, :value_text).to_h
    end

    def parse_date(value)
      return nil if value.blank?

      Date.parse(value.to_s)
    rescue ArgumentError
      nil
    end

    def round_up_to_step(timestamp)
      rounded = timestamp.change(sec: 0)
      remainder = rounded.min % SLOT_STEP_MINUTES
      return rounded if remainder.zero?

      rounded + (SLOT_STEP_MINUTES - remainder).minutes
    end

    def window_start_for(date)
      time_zone.local(date.year, date.month, date.day, WINDOW_START_HOUR, 0, 0)
    end

    def window_end_for(date)
      time_zone.local(date.year, date.month, date.day, WINDOW_END_HOUR, 0, 0)
    end

    def time_zone
      @time_zone ||= ActiveSupport::TimeZone[actor.time_zone.presence || Time.zone.name] || Time.zone
    end

    def resolved_tasks_project
      @resolved_tasks_project ||= tasks_project || TasksProjectEnsurer.new(workspace:, actor:).call
    end

    def tasks_project_error_message
      "The Tasks calendar could not be prepared."
    end

    def unavailable_slot_message
      "No open #{duration_minutes}-minute slot is available before this task's deadline."
    end
  end
end
