module Search
  class IndexPageJob < ApplicationJob
    queue_as :default

    def perform(page_id)
      page = Page.find_by(id: page_id)

      if page.present?
        Search::ChunkIndexingService.index_page!(page: page)
      else
        Search::ChunkIndexingService.delete_source!(source_type: SearchChunk::SOURCE_PAGE, source_id: page_id)
      end
    end
  end
end
