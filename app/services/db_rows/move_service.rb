module DbRows
  class MoveService
    class << self
      def call(row:, database:, workspace:, property:, target_value:, target_index:)
        ActiveRecord::Base.transaction do
          assign_property_value!(row: row, workspace: workspace, property: property, target_value: target_value)
          normalize_target_group_positions!(row: row, database: database, property: property, target_value: target_value, target_index: target_index)
        end
      end

      private

      def assign_property_value!(row:, workspace:, property:, target_value:)
        return if property.blank?

        cell = row.db_cells.find_or_initialize_by(db_property: property, workspace: workspace)
        cell.value_text = target_value.to_s
        cell.save!
      end

      def normalize_target_group_positions!(row:, database:, property:, target_value:, target_index:)
        candidate_rows = DbRow.for_database(database).active.ordered.to_a
        grouped_value_map =
          if property.present?
            DbCell.where(db_row_id: candidate_rows.map(&:id), db_property_id: property.id).pluck(:db_row_id, :value_text).to_h
          else
            {}
          end

        grouped_rows = candidate_rows.reject { |candidate| candidate.id == row.id }.select do |candidate|
          property.blank? || grouped_value_map[candidate.id].to_s == target_value.to_s
        end

        insertion_index = [ target_index.to_i, 0 ].max
        insertion_index = [ insertion_index, grouped_rows.length ].min

        reordered_rows = grouped_rows.dup
        reordered_rows.insert(insertion_index, row)

        reordered_rows.each_with_index do |entry, index|
          position = (index + 1) * DbRow::POSITION_GAP
          next if entry.position == position

          entry.update_columns(position: position, updated_at: Time.current)
        end
      end
    end
  end
end
