module Api
  module V1
    module Kalendarium
      class CalendarsController < BaseController
        before_action :set_workspace!

        def index
          calendars = policy_scope(KalendariumCalendar).for_workspace(workspace).order(:name)

          render json: { data: Api::V1::Serializers::KalendariumCalendarSerializer.render_collection(calendars) }, status: :ok
        end
      end
    end
  end
end
