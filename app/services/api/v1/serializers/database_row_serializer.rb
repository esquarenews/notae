module Api
  module V1
    module Serializers
      class DatabaseRowSerializer
        def self.render_collection(rows, cells:)
          cells_by_row = cells.group_by(&:db_row_id)
          rows.map { |row| render(row, cells: Array(cells_by_row[row.id])) }
        end

        def self.render(row, cells:)
          {
            id: row.id,
            workspace_id: row.workspace_id,
            database_id: row.database_id,
            linked_page_id: row.linked_page_id,
            linked_page: serialize_linked_page(row.linked_page),
            title: row.title,
            position: row.position,
            archived_at: row.archived_at&.iso8601(6),
            data_json: row.data_json,
            created_at: row.created_at&.iso8601(6),
            updated_at: row.updated_at&.iso8601(6),
            cells: serialize_cells(cells)
          }
        end

        def self.serialize_linked_page(page)
          return nil if page.blank?

          {
            id: page.id,
            title: page.title
          }
        end

        def self.serialize_cells(cells)
          Array(cells).map do |cell|
            {
              id: cell.id,
              db_property_id: cell.db_property_id,
              value_text: cell.value_text,
              created_at: cell.created_at&.iso8601(6),
              updated_at: cell.updated_at&.iso8601(6)
            }
          end
        end
      end
    end
  end
end
