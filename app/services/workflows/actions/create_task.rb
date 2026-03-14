module Workflows
  module Actions
    class CreateTask
      def initialize(workflow_run:)
        @workflow_run = workflow_run
      end

      def call
        database = workflow_run.workspace.databases.active.find(workflow_run.input_json["database_id"])
        title = workflow_run.input_json["title"].to_s.strip
        raise ArgumentError, "Task title is required" if title.blank?

        row = database.db_rows.create!(workspace: workflow_run.workspace, title: title)
        seed_cells!(database: database, row: row)
        row.sync_data_from_cells!

        {
          "target_type" => "DbRow",
          "target_id" => row.id,
          "title" => row.title,
          "url" => Rails.application.routes.url_helpers.database_path(
            workspace_slug: workflow_run.workspace.slug,
            id: database.id,
            anchor: "row_#{row.id}"
          )
        }
      end

      private

      attr_reader :workflow_run

      def seed_cells!(database:, row:)
        properties = database.db_properties.ordered.to_a
        return if properties.empty?

        now = Time.current
        cells = properties.map do |property|
          {
            id: SecureRandom.uuid,
            workspace_id: database.workspace_id,
            db_row_id: row.id,
            db_property_id: property.id,
            value_text: value_for_property(property),
            created_at: now,
            updated_at: now
          }
        end

        DbCell.insert_all(cells, unique_by: :index_db_cells_on_db_row_id_and_db_property_id)
      end

      def value_for_property(property)
        name = property.name.to_s.strip.downcase
        return "not started" if name == "status" && property.select?
        return workflow_run.input_json["owner_name"].to_s.strip if name.include?("owner")
        return workflow_run.input_json["due_on"].to_s.strip if property.date? && name.include?("due")
        return workflow_run.input_json["body"].to_s if property.text? && %w[notes description details].include?(name)
        return Date.current.iso8601 if property.date? && name == "date created"

        ""
      end
    end
  end
end
