module Workflows
  module Actions
    class CreateTask
      def initialize(workflow_run:)
        @workflow_run = workflow_run
      end

      def call
        database = Pundit.policy_scope!(workflow_run.user, Database)
                         .for_workspace(workflow_run.workspace)
                         .active
                         .find(workflow_run.input_json["database_id"])
        database.lock!
        raise ArgumentError, "Grid is locked. Unlock it before adding rows." if database.locked?

        title = workflow_run.input_json["title"].to_s.strip
        raise ArgumentError, "Task title is required" if title.blank?

        row = database.db_rows.new(workspace: workflow_run.workspace, title: title)
        Pundit.authorize(workflow_run.user, row, :create?)
        row.save!
        seed_cells!(database: database, row: row)
        Pundit.authorize(workflow_run.user, row, :update?)
        row.sync_data_from_cells!
        row.reload

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
        validate_explicit_cells!(properties)
        return if properties.empty?

        properties.each do |property|
          cell = row.db_cells.new(
            workspace: database.workspace,
            db_property: property,
            value_text: value_for_property(property)
          )
          Pundit.authorize(workflow_run.user, cell, :create?)
          cell.save!
        end
      end

      def value_for_property(property)
        name = property.name.to_s.strip.downcase
        return explicit_cells.fetch(name) if explicit_cells.key?(name)
        return "not started" if name == "status" && property.select?
        return workflow_run.input_json["owner_name"].to_s.strip if name.include?("owner")
        return workflow_run.input_json["due_on"].to_s.strip if property.date? && name.include?("due")
        return workflow_run.input_json["body"].to_s if property.text? && %w[notes description details].include?(name)
        return Date.current.iso8601 if property.date? && name == "date created"

        ""
      end

      def explicit_cells
        @explicit_cells ||= Array(workflow_run.input_json["cells"]).each_with_object({}) do |raw_cell, values|
          cell = raw_cell.to_h.stringify_keys
          property_name = cell["property"].to_s.strip
          raise ArgumentError, "Every cell requires a property name" if property_name.blank?

          values[property_name.downcase] = cell["value"].to_s
        end
      end

      def validate_explicit_cells!(properties)
        property_names = properties.index_by { |property| property.name.to_s.strip.downcase }
        unknown_names = explicit_cells.keys - property_names.keys
        return if unknown_names.empty?

        raise ArgumentError, "Unknown database properties: #{unknown_names.join(', ')}"
      end
    end
  end
end
