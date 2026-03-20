module Search
  class IndexEpistulariumMessageJob < ApplicationJob
    queue_as :default

    def perform(epistularium_message_id)
      message = EpistulariumMessage.find_by(id: epistularium_message_id)

      if message.present?
        Search::ChunkIndexingService.index_epistularium_message!(epistularium_message: message)
      else
        Search::ChunkIndexingService.delete_source!(
          source_type: SearchChunk::SOURCE_EPISTULARIUM_MESSAGE,
          source_id: epistularium_message_id
        )
      end
    end
  end
end
