module Api
  module V1
    module Kalendarium
      class EventsController < BaseController
        require_api_token_scopes(
          index: ApiToken::SCOPE_CALENDAR_READ,
          create: ApiToken::SCOPE_CALENDAR_WRITE
        )

        DATE_ONLY_PATTERN = /\A\d{4}-\d{2}-\d{2}\z/
        EXPLICIT_OFFSET_PATTERN = /(Z|[+-]\d{2}:\d{2})\z/

        before_action :set_workspace!

        def index
          events = policy_scope(KalendariumEvent).for_workspace(workspace)
          events = events.where(kalendarium_calendar_id: calendar_ids) if calendar_ids.any?
          events = events.where(kalendarium_project_id: params[:project_id]) if params[:project_id].present?
          events = events.for_range(range_start, range_end)
                         .order(:starts_at_utc)

          render json: { data: Api::V1::Serializers::KalendariumEventSerializer.render_collection(events) }, status: :ok
        end

        def create
          calendar = selected_calendar
          event = workspace.kalendarium_events.new(
            event_params.except(
              :kalendarium_calendar_id,
              :starts_at,
              :ends_at,
              :time_zone,
              :meeting_join_url,
              :reminder_offsets_minutes
            ).merge(
              kalendarium_calendar: calendar,
              kalendarium_project: selected_project_for_calendar,
              created_by: current_user,
              updated_by: current_user,
              starts_at_utc: starts_at_utc,
              ends_at_utc: ends_at_utc,
              reminder_offsets_minutes: normalize_offsets(event_params[:reminder_offsets_minutes]),
              metadata_json: event_metadata
            )
          )
          authorize event

          if event.save
            warning = sync_event_to_provider(event)
            render json: {
              data: {
                event: Api::V1::Serializers::KalendariumEventSerializer.render(event),
                url: kalendarium_path(
                  workspace_slug: workspace.slug,
                  view: "day",
                  date: event.starts_at_utc.to_date.iso8601,
                  anchor: "kalendarium_event_#{event.id}"
                ),
                warning: warning
              }.compact
            }, status: :created
          else
            render_validation_errors(event)
          end
        rescue ArgumentError => error
          render_error(code: "validation_failed", message: error.message, status: :unprocessable_entity)
        end

        private

        def range_start
          raw = params[:from].presence || Time.current.beginning_of_day.iso8601
          Time.zone.parse(raw.to_s) || Time.current.beginning_of_day
        rescue ArgumentError
          Time.current.beginning_of_day
        end

        def range_end
          raw = params[:to].presence || (Time.current + 30.days).end_of_day.iso8601
          Time.zone.parse(raw.to_s) || (Time.current + 30.days).end_of_day
        rescue ArgumentError
          (Time.current + 30.days).end_of_day
        end

        def calendar_ids
          Array(params[:calendar_ids]).map(&:to_s).reject(&:blank?)
        end

        def event_params
          params.require(:kalendarium_event).permit(
            :kalendarium_calendar_id,
            :title,
            :description,
            :location,
            :starts_at,
            :ends_at,
            :all_day,
            :time_zone,
            :meeting_capture_enabled,
            :rrule,
            :meeting_join_url,
            reminder_offsets_minutes: []
          )
        end

        def selected_calendar
          @selected_calendar ||= policy_scope(KalendariumCalendar).for_workspace(workspace).find(event_params[:kalendarium_calendar_id])
        end

        def selected_project_for_calendar
          return nil unless selected_calendar.source_kind == "project"

          selected_calendar.kalendarium_project
        end

        def raw_starts_at
          @raw_starts_at ||= begin
            value = parse_event_time(event_params[:starts_at], zone: event_time_zone)
            raise ArgumentError, "Start time must be valid." if value.blank?

            value
          end
        end

        def raw_ends_at
          @raw_ends_at ||= begin
            value = parse_event_time(event_params[:ends_at], zone: event_time_zone)
            raise ArgumentError, "End time must be valid." if value.blank?

            value
          end
        end

        def event_time_zone
          @event_time_zone ||= ActiveSupport::TimeZone[event_params[:time_zone].presence || selected_calendar.time_zone.presence || current_user.time_zone.presence] || Time.zone
        end

        def parse_event_time(value, zone:)
          raw = value.to_s.strip
          return nil if raw.blank?

          parsed =
            if raw.match?(DATE_ONLY_PATTERN) || !raw.match?(EXPLICIT_OFFSET_PATTERN)
              zone.parse(raw)
            else
              Time.iso8601(raw)
            end

          return nil if parsed.blank?

          parsed = parsed.utc
          return parsed unless all_day?

          parsed.in_time_zone(zone)
        rescue ArgumentError, TypeError
          nil
        end

        def all_day?
          @all_day ||= ActiveModel::Type::Boolean.new.cast(event_params[:all_day])
        end

        def normalize_offsets(values)
          Array(values).map(&:to_i).select { |offset| offset >= 0 }.uniq.sort
        end

        def event_metadata
          metadata = {}
          meeting_join_url = event_params[:meeting_join_url].to_s.strip
          metadata["meeting_join_url"] = meeting_join_url if meeting_join_url.present?
          metadata
        end

        def normalized_start_and_end_times
          @normalized_start_and_end_times ||= begin
            start_time = raw_starts_at
            end_time = raw_ends_at

            if all_day?
              start_time = start_time.beginning_of_day
              end_time = end_time.end_of_day
              start_time = start_time.in_time_zone(event_time_zone).utc
              end_time = end_time.in_time_zone(event_time_zone).utc
            end

            raise ArgumentError, "End time must be after start time." if end_time <= start_time

            [ start_time, end_time ]
          end
        end

        def starts_at_utc
          normalized_start_and_end_times.first
        end

        def ends_at_utc
          normalized_start_and_end_times.last
        end

        def sync_event_to_provider(event)
          return nil if event.kalendarium_calendar.kalendarium_connection.blank?

          ::Kalendarium::ProviderEventSyncService.new(event: event).upsert_remote!
          clear_pending_sync_marker!(event)
          nil
        rescue StandardError => error
          mark_pending_sync!(event, error: error)
          "Event saved locally, but remote sync failed: #{error.message}"
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
    end
  end
end
