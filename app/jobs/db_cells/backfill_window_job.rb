module DbCells
  class BackfillWindowJob < ApplicationJob
    queue_as :default

    def perform(database_id, row_ids, property_ids)
      database = Database.find_by(id: database_id)
      return if database.blank?

      DbCells::BackfillService.call(
        database: database,
        workspace: database.workspace,
        row_ids: row_ids,
        property_ids: property_ids
      )
    end
  end
end
