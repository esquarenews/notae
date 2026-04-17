module Notifications
  class DailyAgendaBuilder
    DEFAULT_LIMIT = 5

    def initialize(user:, workspace:, date:, limit: DEFAULT_LIMIT)
      @user = user
      @workspace = workspace
      @date = date
      @limit = limit
    end

    def call
      return empty_payload unless events_available?

      agenda_events = ordered_events

      {
        "daily_agenda_date" => local_date.iso8601,
        "daily_agenda_items" => agenda_events.first(limit).map { |event| serialize_event(event) },
        "daily_agenda_total_count" => agenda_events.length,
        "daily_agenda_empty" => agenda_events.empty?
      }
    rescue ActiveRecord::StatementInvalid => error
      raise unless optional_schema_error?(error)

      empty_payload
    end

    private

    attr_reader :user, :workspace, :date, :limit

    def ordered_events
      event_scope.to_a.sort_by do |event|
        [ event.all_day? ? 0 : 1, event.starts_at_utc, event.ends_at_utc, event.title.to_s.downcase ]
      end
    end

    def event_scope
      KalendariumEvent
        .for_workspace(workspace)
        .where.not(status: "cancelled")
        .for_range(local_day_start.utc, local_day_end.utc)
        .select(:id, :title, :starts_at_utc, :ends_at_utc, :all_day)
    end

    def serialize_event(event)
      {
        "id" => event.id,
        "title" => event.title.to_s.squish,
        "time" => time_label_for(event),
        "all_day" => event.all_day?,
        "starts_at" => event.starts_at_utc&.iso8601,
        "ends_at" => event.ends_at_utc&.iso8601
      }
    end

    def time_label_for(event)
      return "All day" if event.all_day?

      event.starts_at_utc.in_time_zone(time_zone).strftime("%H:%M")
    end

    def local_date
      @local_date ||= date.respond_to?(:to_date) ? date.to_date : Date.iso8601(date.to_s)
    rescue ArgumentError
      current_local_date
    end

    def current_local_date
      Time.use_zone(time_zone) { Date.current }
    end

    def local_day_start
      @local_day_start ||= time_zone.local(local_date.year, local_date.month, local_date.day).beginning_of_day
    end

    def local_day_end
      @local_day_end ||= local_day_start.end_of_day
    end

    def time_zone
      @time_zone ||= ActiveSupport::TimeZone[user&.time_zone.presence] || Time.zone || ActiveSupport::TimeZone["UTC"]
    end

    def empty_payload
      {
        "daily_agenda_date" => local_date.iso8601,
        "daily_agenda_items" => [],
        "daily_agenda_total_count" => 0,
        "daily_agenda_empty" => true
      }
    end

    def events_available?
      ActiveRecord::Base.connection.data_source_exists?("kalendarium_events")
    end

    def optional_schema_error?(error)
      message = [ error.message, error.cause&.message ].compact.join(" ")
      message.include?("PG::UndefinedTable") ||
        message.include?("PG::UndefinedColumn") ||
        message.include?("no such table") ||
        message.include?("no such column") ||
        (message.include?("relation") && message.include?("does not exist"))
    end
  end
end
