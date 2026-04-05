module DbCells
  class BackfillService
    def self.call(database:, workspace:, row_ids:, property_ids:)
      row_ids = Array(row_ids).map(&:to_s).reject(&:blank?)
      property_ids = Array(property_ids).map(&:to_s).reject(&:blank?)
      return if row_ids.empty? || property_ids.empty?

      existing_scope = DbCell.for_database(database).where(db_row_id: row_ids, db_property_id: property_ids)
      expected_count = row_ids.length * property_ids.length
      return if expected_count <= 0
      return if existing_scope.count >= expected_count

      existing_keys = existing_scope.pluck(:db_row_id, :db_property_id).to_set
      now = Time.current
      missing_cells = []

      row_ids.each do |row_id|
        property_ids.each do |property_id|
          next if existing_keys.include?([ row_id, property_id ])

          missing_cells << {
            id: SecureRandom.uuid,
            workspace_id: workspace.id,
            db_row_id: row_id,
            db_property_id: property_id,
            value_text: "",
            created_at: now,
            updated_at: now
          }
        end
      end

      return if missing_cells.empty?

      DbCell.insert_all(missing_cells, unique_by: :index_db_cells_on_db_row_id_and_db_property_id)
    end
  end
end
