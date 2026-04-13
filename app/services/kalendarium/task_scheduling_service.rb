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

    SchedulingProfile = Struct.new(
      :task_mode,
      :allow_early_work,
      :lookahead_days,
      :urgent_status,
      keyword_init: true
    )

    DEFAULT_DURATION_MINUTES = 20
    DEFAULT_CANDIDATE_LIMIT = 4
    SLOT_STEP_MINUTES = 5
    SUGGESTION_SPACING_MINUTES = 60
    PREFERRED_BUFFER_MINUTES = 15
    WORKDAY_START_HOUR = 9
    WORKDAY_END_HOUR = 17
    EARLY_WORKDAY_START_HOUR = 6
    PERSONAL_WEEKDAY_START_HOUR = 18
    PERSONAL_WEEKDAY_END_HOUR = 21
    PERSONAL_WEEKEND_START_HOUR = 9
    PERSONAL_WEEKEND_END_HOUR = 18
    DEFAULT_LOOKAHEAD_DAYS = 7
    URGENT_LOOKAHEAD_DAYS = 2
    MAX_SEARCH_DAYS = 21
    ESTABLISHED_PROPERTY_PATTERN = /\A(date created|created|established|start date)\z/i
    DEADLINE_PROPERTY_PATTERN = /\A(due(?: date)?|deadline|end(?: date)?)\z/i
    STATUS_PROPERTY_PATTERN = /\Astatus\z/i
    TASK_STATUS_NORMALIZATION_MAP = {
      "planning" => "not started",
      "on hold" => "hold",
      "complete" => "done",
      "completed" => "done",
      "in progress" => "started"
    }.freeze
    URGENT_STATUS_VALUES = [ "not started", "overdue" ].freeze
    WORK_KEYWORDS = %w[
      client company contract deck engineering follow-up invoice launch meeting office product
      project proposal report review roadmap sprint stakeholder strategy team vendor work
    ].freeze
    PERSONAL_KEYWORDS = %w[
      appointment bank birthday dentist dinner doctor family finance groceries grocery gym home
      holiday kids laundry meal mortgage personal pharmacy school shopping vacation vet workout
    ].freeze
    PERSONAL_SIGNAL_PATTERN = /\b(personal|home|family|kids|shopping|groceries|doctor|dentist|gym|holiday|vacation)\b/i
    WORK_SIGNAL_PATTERN = /\b(work|client|project|team|meeting|roadmap|launch|proposal|stakeholder|office|invoice|vendor)\b/i
    EARLY_WORK_REQUEST_PATTERN = /
      \b(before\s+9|before\s+work|early\s+(?:morning|start)|first\s+thing|7(?::[0-5]\d)?\s*am|8(?::[0-5]\d)?\s*am)\b
    /ix

    def initialize(workspace:, row:, actor:, duration_minutes: DEFAULT_DURATION_MINUTES, tasks_project: nil, busy_calendar_ids: nil, visible_project_ids: nil)
      @workspace = workspace
      @row = row
      @actor = actor
      @duration_minutes = duration_minutes.to_i.positive? ? duration_minutes.to_i : DEFAULT_DURATION_MINUTES
      @tasks_project = tasks_project
      @busy_calendar_ids = busy_calendar_ids.nil? ? nil : Array(busy_calendar_ids).compact.uniq
      @visible_project_ids = visible_project_ids.nil? ? nil : Array(visible_project_ids).compact.uniq
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

    def candidate_slots(limit: DEFAULT_CANDIDATE_LIMIT)
      project = resolved_tasks_project
      return CandidateResult.new(slots: [], error: tasks_project_error_message) if project.blank? || project.kalendarium_calendar.blank?

      lower_bound = earliest_start_time
      upper_bound = search_upper_bound(lower_bound)

      if upper_bound <= lower_bound
        return CandidateResult.new(slots: [], error: unavailable_slot_message(lower_bound:, upper_bound:))
      end

      buffered_slots = available_slots(limit:, lower_bound:, upper_bound:, buffer_minutes: PREFERRED_BUFFER_MINUTES)
      fallback_slots =
        if buffered_slots.size < limit
          available_slots(limit:, lower_bound:, upper_bound:, buffer_minutes: 0)
        else
          []
        end
      slots = merge_unique_slots(buffered_slots, fallback_slots).first(limit)
      if slots.blank?
        return CandidateResult.new(slots: [], error: unavailable_slot_message(lower_bound:, upper_bound:))
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

    def slot_available?(starts_at:, ends_at:, manual_override: false)
      availability_error(starts_at:, ends_at:, manual_override:).blank?
    end

    def availability_error(starts_at:, ends_at:, manual_override: false)
      starts_local = starts_at.in_time_zone(time_zone)
      ends_local = ends_at.in_time_zone(time_zone)
      return "Choose a valid start and end time." if ends_local <= starts_local

      lower_bound = earliest_start_time

      if starts_local < lower_bound
        return "This task needs to be scheduled in the future."
      end

      deadline_end = deadline_date&.in_time_zone(time_zone)&.end_of_day
      if deadline_end.present? && ends_local > deadline_end
        return "This task needs to be scheduled before its deadline."
      end

      unless manual_override
        upper_bound = search_upper_bound(lower_bound)
        if ends_local > upper_bound
          return "That time is outside the current scheduling window."
        end

        unless slot_within_lookahead_window?(starts_at: starts_local, lower_bound:)
          return "That time falls outside the current #{scheduling_profile.lookahead_days}-day scheduling window."
        end

        unless slot_within_allowed_windows?(starts_at: starts_local, ends_at: ends_local)
          return scheduling_window_error_message
        end
      end

      intervals = merged_busy_intervals(
        lower_bound: starts_local.beginning_of_day,
        upper_bound: ends_local.end_of_day,
        buffer_minutes: 0
      )
      overlapping_interval = intervals.find do |interval|
        interval[:start_at] < ends_local && interval[:end_at] > starts_local
      end
      return "That time overlaps another calendar event." if overlapping_interval.present?

      nil
    end

    def suggestion_notice(slot_count:)
      count = slot_count.to_i
      return "No available slots matched this task." if count <= 0

      count_label = "#{count} available #{count == 1 ? "slot" : "slots"}"
      "#{count_label} in #{schedule_notice_window_label} over the next #{scheduling_profile.lookahead_days} #{'day'.pluralize(scheduling_profile.lookahead_days)} in Kalendarium."
    end

    private

    attr_reader :workspace, :row, :actor, :duration_minutes, :tasks_project, :busy_calendar_ids, :visible_project_ids

    def earliest_start_time
      [
        Time.current.in_time_zone(time_zone),
        established_date&.in_time_zone(time_zone)&.beginning_of_day
      ].compact.max
    end

    def search_upper_bound(lower_bound)
      deadline = deadline_date
      fallback = lower_bound + MAX_SEARCH_DAYS.days
      return fallback if deadline.blank?

      deadline_end = deadline.in_time_zone(time_zone).end_of_day
      [ deadline_end, fallback ].min
    end

    def available_slots(limit:, lower_bound:, upper_bound:, buffer_minutes:)
      intervals = merged_busy_intervals(lower_bound:, upper_bound:, buffer_minutes:)
      cursor_date = lower_bound.to_date
      slots_by_day = []
      eligible_days_seen = 0

      while cursor_date <= upper_bound.to_date && eligible_days_seen < scheduling_profile.lookahead_days
        day_windows = scheduling_windows_for(cursor_date)
        eligible_day = day_eligible?(windows: day_windows, lower_bound:, upper_bound:)
        if eligible_day
          slots_by_day << available_slots_for_day(
            cursor_date,
            lower_bound:,
            upper_bound:,
            intervals:,
            limit:,
            windows: day_windows
          )
          eligible_days_seen += 1
        end

        cursor_date += 1.day
      end

      interleave_slots_by_day(slots_by_day, limit)
    end

    def available_slots_for_day(date, lower_bound:, upper_bound:, intervals:, limit:, windows:)
      day_slots = []

      windows.each do |window|
        window_start = [ lower_bound, window[:start_at] ].max
        window_end = [ upper_bound, window[:end_at] ].min
        next unless window_end > window_start

        candidate_start = round_up_to_step(window_start)

        while (candidate_start + duration_minutes.minutes) <= window_end && day_slots.size < limit
          candidate_end = candidate_start + duration_minutes.minutes
          overlapping_interval = intervals.find do |interval|
            interval[:start_at] < candidate_end && interval[:end_at] > candidate_start
          end

          if overlapping_interval.blank?
            day_slots << Slot.new(starts_at: candidate_start, ends_at: candidate_end)
            candidate_start = round_up_to_step(candidate_end + SUGGESTION_SPACING_MINUTES.minutes)
            next
          end

          candidate_start = round_up_to_step([ overlapping_interval[:end_at], candidate_start + SLOT_STEP_MINUTES.minutes ].max)
        end
      end

      day_slots
    end

    def merged_busy_intervals(lower_bound:, upper_bound:, buffer_minutes:)
      busy_intervals = busy_events(lower_bound:, upper_bound:).map do |event|
        event_start = event.starts_at_utc.in_time_zone(time_zone) - buffer_minutes.minutes
        event_end = event.ends_at_utc.in_time_zone(time_zone) + buffer_minutes.minutes
        {
          start_at: [ event_start, lower_bound ].max,
          end_at: [ event_end, upper_bound ].min
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
      calendar_ids = scoped_busy_calendar_ids
      workspace_events =
        if calendar_ids.empty?
          []
        else
          scope = KalendariumEvent
            .for_workspace(workspace)
            .where(kalendarium_calendar_id: calendar_ids)
            .where(all_day: [ false, nil ])
            .where.not(status: "cancelled")
            .for_range(lower_bound.utc, upper_bound.utc)
          scope =
            if visible_project_ids.nil?
              scope
            elsif visible_project_ids.any?
              scope.where(
                "kalendarium_events.kalendarium_project_id IS NULL OR kalendarium_events.kalendarium_project_id IN (?)",
                visible_project_ids
              )
            else
              scope.where(kalendarium_project_id: nil)
            end

          scope.order(:starts_at_utc).to_a
        end

      external_task_events = Pundit.policy_scope!(actor, KalendariumEvent)
        .where.not(workspace_id: workspace.id)
        .where(created_by_id: actor.id)
        .joins(:kalendarium_project)
        .where(kalendarium_projects: { slug: TasksProjectEnsurer::PROJECT_SLUG })
        .where(all_day: [ false, nil ])
        .where.not(status: "cancelled")
        .for_range(lower_bound.utc, upper_bound.utc)
        .order(:starts_at_utc)
        .to_a

      (workspace_events + external_task_events).uniq(&:id).sort_by(&:starts_at_utc)
    end

    def established_date
      date_for_matching_property(ESTABLISHED_PROPERTY_PATTERN)
    end

    def deadline_date
      date_for_matching_property(DEADLINE_PROPERTY_PATTERN)
    end

    def status_value
      property = ordered_properties.find do |db_property|
        db_property.name.to_s.match?(STATUS_PROPERTY_PATTERN)
      end
      return nil if property.blank?

      normalize_status_value(row_cells_by_property_id[property.id])
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

    def normalize_status_value(value)
      normalized = value.to_s.strip.downcase
      TASK_STATUS_NORMALIZATION_MAP.fetch(normalized, normalized)
    end

    def merge_unique_slots(primary_slots, fallback_slots)
      (Array(primary_slots) + Array(fallback_slots)).uniq do |slot|
        [ slot.starts_at.to_i, slot.ends_at.to_i ]
      end
    end

    def interleave_slots_by_day(slots_by_day, limit)
      ordered_slots = []
      slot_index = 0

      while ordered_slots.size < limit
        added_in_round = false

        slots_by_day.each do |day_slots|
          slot = day_slots[slot_index]
          next if slot.blank?

          ordered_slots << slot
          added_in_round = true
          return ordered_slots if ordered_slots.size >= limit
        end

        break unless added_in_round

        slot_index += 1
      end

      ordered_slots
    end

    def day_eligible?(windows:, lower_bound:, upper_bound:)
      windows.any? do |window|
        [ lower_bound, window[:start_at] ].max < [ upper_bound, window[:end_at] ].min
      end
    end

    def scheduling_profile
      @scheduling_profile ||= SchedulingProfile.new(
        task_mode: infer_task_mode,
        allow_early_work: early_work_requested?,
        lookahead_days: URGENT_STATUS_VALUES.include?(status_value) ? URGENT_LOOKAHEAD_DAYS : DEFAULT_LOOKAHEAD_DAYS,
        urgent_status: URGENT_STATUS_VALUES.include?(status_value)
      )
    end

    def infer_task_mode
      signal_text = task_signal_text
      return :personal if signal_text.match?(PERSONAL_SIGNAL_PATTERN)
      return :work if signal_text.match?(WORK_SIGNAL_PATTERN)

      work_score = keyword_score(signal_text, WORK_KEYWORDS)
      personal_score = keyword_score(signal_text, PERSONAL_KEYWORDS)
      personal_score > work_score ? :personal : :work
    end

    def keyword_score(text, keywords)
      keywords.sum { |keyword| text.match?(/\b#{Regexp.escape(keyword)}\b/) ? 1 : 0 }
    end

    def task_signal_text
      @task_signal_text ||= begin
        property_lines = ordered_properties.filter_map do |property|
          value = row_cells_by_property_id[property.id].to_s.strip
          next if value.blank?

          "#{property.name}: #{value}"
        end

        [
          row.database.name,
          row.title,
          property_lines.join("\n")
        ].compact.join("\n").downcase
      end
    end

    def early_work_requested?
      return false unless infer_task_mode == :work

      task_signal_text.match?(EARLY_WORK_REQUEST_PATTERN)
    end

    def scheduling_windows_for(date)
      if scheduling_profile.task_mode == :work
        return [] if weekend?(date)

        start_hour = scheduling_profile.allow_early_work ? EARLY_WORKDAY_START_HOUR : WORKDAY_START_HOUR
        return [ { start_at: local_time_for(date, start_hour), end_at: local_time_for(date, WORKDAY_END_HOUR) } ]
      end

      if weekend?(date)
        [
          {
            start_at: local_time_for(date, PERSONAL_WEEKEND_START_HOUR),
            end_at: local_time_for(date, PERSONAL_WEEKEND_END_HOUR)
          }
        ]
      else
        [
          {
            start_at: local_time_for(date, PERSONAL_WEEKDAY_START_HOUR),
            end_at: local_time_for(date, PERSONAL_WEEKDAY_END_HOUR)
          }
        ]
      end
    end

    def slot_within_allowed_windows?(starts_at:, ends_at:)
      return false unless starts_at.to_date == ends_at.to_date

      scheduling_windows_for(starts_at.to_date).any? do |window|
        starts_at >= window[:start_at] && ends_at <= window[:end_at]
      end
    end

    def slot_within_lookahead_window?(starts_at:, lower_bound:)
      eligible_days_seen = 0
      cursor_date = lower_bound.to_date

      while cursor_date <= starts_at.to_date
        day_windows = scheduling_windows_for(cursor_date)
        eligible_days_seen += 1 if day_eligible?(windows: day_windows, lower_bound:, upper_bound: starts_at.end_of_day)
        return true if cursor_date == starts_at.to_date && eligible_days_seen <= scheduling_profile.lookahead_days

        cursor_date += 1.day
      end

      false
    end

    def scheduling_window_error_message
      if scheduling_profile.task_mode == :work
        return "Work tasks are scheduled on weekdays between 9:00 AM and 5:00 PM." unless scheduling_profile.allow_early_work

        "Work tasks are scheduled on weekdays, with early starts only when the task asks for them."
      else
        "Personal tasks are scheduled after hours on weekdays and during weekends."
      end
    end

    def schedule_notice_window_label
      scheduling_profile.task_mode == :work ? "weekday work hours" : "after-hours and weekend windows"
    end

    def round_up_to_step(timestamp)
      rounded = timestamp.change(sec: 0)
      remainder = rounded.min % SLOT_STEP_MINUTES
      return rounded if remainder.zero?

      rounded + (SLOT_STEP_MINUTES - remainder).minutes
    end

    def local_time_for(date, hour)
      time_zone.local(date.year, date.month, date.day, hour, 0, 0)
    end

    def weekend?(date)
      date.saturday? || date.sunday?
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

    def unavailable_slot_message(lower_bound: nil, upper_bound: nil)
      lower_bound ||= earliest_start_time
      upper_bound ||= search_upper_bound(lower_bound)
      deadline_label = deadline_date.present? ? " before this task's deadline" : ""
      [
        "No open #{duration_minutes}-minute slot is available in #{schedule_notice_window_label} over the next #{scheduling_profile.lookahead_days} #{'day'.pluralize(scheduling_profile.lookahead_days)}#{deadline_label}.",
        unavailability_diagnostic_message(lower_bound:, upper_bound:)
      ].join(" ")
    end

    def unavailability_diagnostic_message(lower_bound:, upper_bound:)
      mode_label = scheduling_profile.task_mode == :work ? "work" : "personal"
      normalized_status = status_value.presence || "unset"
      eligible_days = eligible_day_count(lower_bound:, upper_bound:)
      scoped_calendar_count = scoped_busy_calendar_ids.size
      busy_event_count = busy_events(lower_bound:, upper_bound:).size

      summary = "This task is being treated as a #{mode_label} task with status \"#{normalized_status}\", so only #{diagnostic_window_label} were checked."
      visibility_note =
        if busy_calendar_ids.nil?
          "Scheduling checks all enabled calendars, not only the ones currently visible in the split view."
        else
          "Scheduling only checks calendars that are currently visible in this Kalendarium view."
        end

      if eligible_days.zero?
        return [
          summary,
          "No eligible #{schedule_notice_window_label} fall inside the current search window.",
          visibility_note
        ].join(" ")
      end

      [
        summary,
        "Checked #{eligible_days} eligible #{'day'.pluralize(eligible_days)} across #{scoped_calendar_count} #{busy_calendar_ids.nil? ? "enabled" : "visible"} #{'calendar'.pluralize(scoped_calendar_count)} and found #{busy_event_count} timed #{'event'.pluralize(busy_event_count)} in that window.",
        visibility_note
      ].join(" ")
    end

    def scoped_busy_calendar_ids
      @scoped_busy_calendar_ids ||= begin
        if busy_calendar_ids.present? || busy_calendar_ids == []
          busy_calendar_ids
        else
          workspace.kalendarium_calendars.enabled.pluck(:id)
        end
      end
    end

    def eligible_day_count(lower_bound:, upper_bound:)
      cursor_date = lower_bound.to_date
      eligible_days = 0

      while cursor_date <= upper_bound.to_date && eligible_days < scheduling_profile.lookahead_days
        day_windows = scheduling_windows_for(cursor_date)
        eligible_days += 1 if day_eligible?(windows: day_windows, lower_bound:, upper_bound:)
        cursor_date += 1.day
      end

      eligible_days
    end

    def diagnostic_window_label
      if scheduling_profile.task_mode == :work
        return "weekday 9:00 AM to 5:00 PM windows" unless scheduling_profile.allow_early_work

        "weekday work-hour windows with early starts allowed"
      else
        "after-hours weekday and weekend windows"
      end
    end
  end
end
