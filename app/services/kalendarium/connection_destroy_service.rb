module Kalendarium
  class ConnectionDestroyService
    def initialize(connection:)
      @connection = connection
    end

    def call
      calendar_ids = connection.kalendarium_calendars.pluck(:id)
      return connection.delete if calendar_ids.empty?

      event_ids = KalendariumEvent.where(kalendarium_calendar_id: calendar_ids).pluck(:id)

      ActiveRecord::Base.transaction do
        if event_ids.any?
          KalendariumWriteProposal.where(kalendarium_event_id: event_ids).update_all(
            kalendarium_event_id: nil,
            updated_at: Time.current
          )
          MeetingSession.where(kalendarium_event_id: event_ids).update_all(
            kalendarium_event_id: nil,
            updated_at: Time.current
          )
          SearchChunk.where(source_type: SearchChunk::SOURCE_KALENDARIUM_EVENT, source_id: event_ids).delete_all
          SearchChunk.where(kalendarium_event_id: event_ids).delete_all
          KalendariumEvent.where(id: event_ids).delete_all
        end

        KalendariumProject.where(kalendarium_calendar_id: calendar_ids).update_all(
          kalendarium_calendar_id: nil,
          updated_at: Time.current
        )
        KalendariumCalendar.where(id: calendar_ids).delete_all
        connection.delete
      end
    end

    private

    attr_reader :connection
  end
end
