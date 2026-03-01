module Api
  module V1
    module Kalendarium
      class EventsController < BaseController
        before_action :set_workspace!

        def index
          events = policy_scope(KalendariumEvent).for_workspace(workspace)
          events = events.where(kalendarium_calendar_id: calendar_ids) if calendar_ids.any?
          events = events.where(kalendarium_project_id: params[:project_id]) if params[:project_id].present?
          events = events.for_range(range_start, range_end)
                         .order(:starts_at_utc)

          render json: { data: Api::V1::Serializers::KalendariumEventSerializer.render_collection(events) }, status: :ok
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
      end
    end
  end
end
