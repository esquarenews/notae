module Kalendarium
  class RecurrenceExpander
    WEEKDAY_CODES = {
      "SU" => 0,
      "MO" => 1,
      "TU" => 2,
      "WE" => 3,
      "TH" => 4,
      "FR" => 5,
      "SA" => 6
    }.freeze
    MAX_OCCURRENCES_PER_EVENT = 1_000

    def initialize(events:, range_start:, range_end:, time_zone:)
      @events = Array(events)
      @range_start = range_start
      @range_end = range_end
      @time_zone = ActiveSupport::TimeZone[time_zone] || Time.zone
    end

    def call
      events.flat_map { |event| occurrences_for(event) }
            .sort_by { |event| [ event.starts_at_utc, event.id.to_s, occurrence_sort_key(event) ] }
    end

    private

    attr_reader :events, :range_start, :range_end, :time_zone

    def occurrences_for(event)
      rrule = parse_rrule(event.rrule)
      return event_overlaps_range?(event) ? [ event ] : [] if rrule.blank?

      duration_seconds = [ event.ends_at_utc - event.starts_at_utc, 60 ].max
      occurrence_starts(event, rrule).filter_map do |starts_local|
        starts_at_utc = starts_local.utc
        ends_at_utc = starts_at_utc + duration_seconds
        next unless starts_at_utc < range_end && ends_at_utc > range_start

        occurrence_for(event, starts_at_utc:, ends_at_utc:)
      end
    end

    def occurrence_starts(event, rrule)
      starts_local = event.starts_at_utc.in_time_zone(time_zone)
      Enumerator.new do |yielder|
        generated_count = 0
        case rrule["FREQ"]
        when "DAILY"
          each_daily_start(starts_local, rrule) do |candidate|
            generated_count += 1
            break if stop_generating?(candidate, rrule, generated_count)

            yielder << candidate
          end
        when "WEEKLY"
          each_weekly_start(starts_local, rrule) do |candidate|
            next if candidate < starts_local

            generated_count += 1
            break if stop_generating?(candidate, rrule, generated_count)

            yielder << candidate
          end
        when "MONTHLY"
          each_monthly_start(starts_local, rrule) do |candidate|
            generated_count += 1
            break if stop_generating?(candidate, rrule, generated_count)

            yielder << candidate
          end
        else
          generated_count += 1
          yielder << starts_local unless stop_generating?(starts_local, rrule, generated_count)
        end
      end.take(MAX_OCCURRENCES_PER_EVENT)
    end

    def each_daily_start(starts_local, rrule)
      interval = positive_interval(rrule)
      candidate = starts_local
      loop do
        yield candidate
        candidate += interval.days
        break if candidate.utc >= range_end + 1.year
      end
    end

    def each_weekly_start(starts_local, rrule)
      interval = positive_interval(rrule)
      weekdays = recurrence_weekdays(rrule, starts_local)
      week_start = starts_local.to_date - starts_local.to_date.wday.days

      loop do
        weekdays.each do |weekday|
          candidate_date = week_start + weekday.days
          yield time_zone.local(candidate_date.year, candidate_date.month, candidate_date.day, starts_local.hour, starts_local.min, starts_local.sec)
        end
        week_start += interval.weeks
        break if week_start.beginning_of_day.utc >= range_end + 1.year
      end
    end

    def each_monthly_start(starts_local, rrule)
      interval = positive_interval(rrule)
      candidate = starts_local
      loop do
        yield candidate
        candidate += interval.months
        break if candidate.utc >= range_end + 1.year
      end
    end

    def stop_generating?(candidate, rrule, generated_count)
      count_limit = rrule["COUNT"].to_i
      return true if count_limit.positive? && generated_count > count_limit

      until_time = parse_until(rrule["UNTIL"])
      return true if until_time.present? && candidate.utc > until_time

      candidate.utc >= range_end && count_limit.blank? && until_time.blank?
    end

    def recurrence_weekdays(rrule, starts_local)
      raw_days = rrule["BYDAY"].to_s.split(",").map(&:strip).filter_map { |code| WEEKDAY_CODES[code] }
      days = raw_days.presence || [ starts_local.to_date.wday ]
      days.uniq.sort
    end

    def positive_interval(rrule)
      [ rrule["INTERVAL"].to_i, 1 ].max
    end

    def parse_rrule(raw_rrule)
      normalized_rrule = raw_rrule.to_s.sub(/\ARRULE:/i, "")
      normalized_rrule.split(";").each_with_object({}) do |entry, index|
        key, value = entry.split("=", 2)
        next if key.blank? || value.blank?

        index[key.upcase] = value.upcase
      end
    end

    def parse_until(raw_until)
      value = raw_until.to_s
      return nil if value.blank?

      if value.match?(/\A\d{8}T\d{6}Z\z/)
        Time.utc(value[0, 4].to_i, value[4, 2].to_i, value[6, 2].to_i, value[9, 2].to_i, value[11, 2].to_i, value[13, 2].to_i)
      elsif value.match?(/\A\d{8}\z/)
        time_zone.local(value[0, 4].to_i, value[4, 2].to_i, value[6, 2].to_i, 23, 59, 59).utc
      end
    rescue ArgumentError
      nil
    end

    def event_overlaps_range?(event)
      event.starts_at_utc < range_end && event.ends_at_utc > range_start
    end

    def occurrence_for(event, starts_at_utc:, ends_at_utc:)
      return event if event.starts_at_utc == starts_at_utc && event.ends_at_utc == ends_at_utc

      KalendariumEventOccurrence.new(
        source_event: event,
        starts_at_utc: starts_at_utc,
        ends_at_utc: ends_at_utc,
        occurrence_key: starts_at_utc.to_i
      )
    end

    def occurrence_sort_key(event)
      event.respond_to?(:occurrence_key) ? event.occurrence_key.to_s : ""
    end
  end
end
