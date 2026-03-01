module Search
  class IndexKalendariumEventJob < ApplicationJob
    queue_as :default

    def perform(kalendarium_event_id)
      event = KalendariumEvent.find_by(id: kalendarium_event_id)

      if event.present?
        Search::ChunkIndexingService.index_kalendarium_event!(kalendarium_event: event)
      else
        Search::ChunkIndexingService.delete_source!(source_type: SearchChunk::SOURCE_KALENDARIUM_EVENT, source_id: kalendarium_event_id)
      end
    end
  end
end
