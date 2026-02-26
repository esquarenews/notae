module Search
  class IndexDbRowJob < ApplicationJob
    queue_as :default

    def perform(db_row_id)
      db_row = DbRow.find_by(id: db_row_id)

      if db_row.present?
        Search::ChunkIndexingService.index_db_row!(db_row: db_row)
      else
        Search::ChunkIndexingService.delete_source!(source_type: SearchChunk::SOURCE_DB_ROW, source_id: db_row_id)
      end
    end
  end
end
