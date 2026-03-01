module Kalendarium
  class ReconcileEventJob < ApplicationJob
    queue_as :default

    def perform(event_id, payload = {})
      event = KalendariumEvent.find_by(id: event_id)
      return if event.blank?

      attrs = payload.to_h.symbolize_keys.slice(:title, :description, :location, :starts_at_utc, :ends_at_utc, :etag, :sequence)
      event.update!(attrs.merge(last_synced_at: Time.current)) if attrs.present?
    end
  end
end
