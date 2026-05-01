module Api
  module V1
    module Serializers
      class DatabaseSerializer
        def self.render_collection(databases)
          databases.map { |database| render_summary(database) }
        end

        def self.render_summary(database)
          {
            id: database.id,
            workspace_id: database.workspace_id,
            name: database.name,
            property_count: database.db_properties.size,
            row_count: database.db_rows.active.size,
            created_at: database.created_at&.iso8601(6),
            updated_at: database.updated_at&.iso8601(6)
          }
        end

        def self.render(database, properties:, rows:, cells:)
          {
            id: database.id,
            workspace_id: database.workspace_id,
            name: database.name,
            created_at: database.created_at&.iso8601(6),
            updated_at: database.updated_at&.iso8601(6),
            properties: serialize_properties(properties),
            rows: serialize_rows(rows, cells)
          }
        end

        def self.serialize_properties(properties)
          properties.map do |property|
            {
              id: property.id,
              name: property.name,
              property_type: property.property_type,
              position: property.position
            }
          end
        end

        def self.serialize_rows(rows, cells)
          DatabaseRowSerializer.render_collection(rows, cells: cells)
        end
      end
    end
  end
end
