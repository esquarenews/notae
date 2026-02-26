module Search
  class BackfillWorkspaceChunksJob < ApplicationJob
    queue_as :default

    def perform(workspace_id)
      workspace = Workspace.find_by(id: workspace_id)
      return if workspace.blank?

      workspace.pages.find_each do |page|
        Search::ChunkIndexingService.index_page!(page: page)
      end

      workspace.db_rows.find_each do |db_row|
        Search::ChunkIndexingService.index_db_row!(db_row: db_row)
      end
    end
  end
end
