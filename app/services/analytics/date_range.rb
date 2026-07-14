module Analytics
  class DateRange
    DEFAULT_PERIOD = "7d".freeze
    MAX_DAYS = 366
    PERIODS = %w[7d 8w mtd 30d 90d year custom].freeze

    attr_reader :start_date, :end_date, :period

    def initialize(params: {}, today: Time.zone.today)
      @today = today
      @period = normalized_period(params[:period])
      @start_date, @end_date = resolve_dates(params)
      normalize_bounds!
    end

    def days
      (end_date - start_date).to_i + 1
    end

    def time_range
      start_date.beginning_of_day..end_date.end_of_day
    end

    def previous_time_range
      previous_end = start_date - 1.day
      previous_start = previous_end - (days - 1).days
      previous_start.beginning_of_day..previous_end.end_of_day
    end

    def grouping
      return :week if period == "8w"
      return :day if days <= 31
      return :week if days <= 180

      :month
    end

    def label
      "#{start_date.strftime("%-d %b %Y")} - #{end_date.strftime("%-d %b %Y")}"
    end

    def to_params
      {
        period: period,
        start_date: start_date.iso8601,
        end_date: end_date.iso8601
      }
    end

    private

    attr_reader :today

    def normalized_period(value)
      candidate = value.to_s
      PERIODS.include?(candidate) ? candidate : DEFAULT_PERIOD
    end

    def resolve_dates(params)
      case period
      when "7d"
        [ today - 6.days, today ]
      when "8w"
        [ today.beginning_of_week - 7.weeks, today ]
      when "mtd"
        [ today.beginning_of_month, today ]
      when "90d"
        [ today - 89.days, today ]
      when "year"
        [ today.beginning_of_year, today ]
      when "custom"
        [ parse_date(params[:start_date]), parse_date(params[:end_date]) ]
      else
        [ today - 29.days, today ]
      end
    end

    def parse_date(value)
      Date.iso8601(value.to_s)
    rescue Date::Error, ArgumentError
      nil
    end

    def normalize_bounds!
      if @start_date.blank? || @end_date.blank? || @start_date > @end_date
        reset_to_default!
      end

      @end_date = [ @end_date, today ].min
      reset_to_default! if @start_date > @end_date
      @start_date = [ @start_date, @end_date - (MAX_DAYS - 1).days ].max
    end

    def reset_to_default!
      @period = DEFAULT_PERIOD
      @start_date = today - 6.days
      @end_date = today
    end
  end
end
