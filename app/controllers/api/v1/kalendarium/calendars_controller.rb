module Api
  module V1
    module Kalendarium
      class CalendarsController < BaseController
        require_api_token_scopes index: ApiToken::SCOPE_CALENDAR_READ

        before_action :set_workspace!

        def index
          calendars = policy_scope(KalendariumCalendar).for_workspace(workspace).order(:name)
          calendars = calendars.enabled.user_writable if writable_only?

          render json: { data: Api::V1::Serializers::KalendariumCalendarSerializer.render_collection(calendars) }, status: :ok
        end

        private

        def writable_only?
          ActiveModel::Type::Boolean.new.cast(params[:writable])
        end
      end
    end
  end
end
