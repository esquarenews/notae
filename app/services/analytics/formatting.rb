module Analytics
  module Formatting
    module_function

    def duration(seconds)
      total_seconds = seconds.to_i.clamp(0, Float::INFINITY).to_i
      return "0 min" if total_seconds.zero?
      return "#{total_seconds} sec" if total_seconds < 60

      hours, remainder = total_seconds.divmod(1.hour.to_i)
      minutes = remainder / 1.minute.to_i
      return "#{minutes} min" if hours.zero?
      return "#{hours} hr" if minutes.zero?

      "#{hours} hr #{minutes} min"
    end

    def percent(value, precision: 0)
      "#{value.to_f.round(precision)}%"
    end
  end
end
