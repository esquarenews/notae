module Workflows
  module Actions
    class CreateDatabase
      def initialize(workflow_run:)
        @workflow_run = workflow_run
      end

      def call
        name = workflow_run.input_json["name"].presence || workflow_run.input_json["title"]
        name = name.to_s.strip
        raise ArgumentError, "Database name is required" if name.blank?

        database = workflow_run.workspace.databases.new(
          name: name,
          description: workflow_run.input_json["description"].to_s,
          created_by: workflow_run.user
        )
        Pundit.authorize(workflow_run.user, database, :create?)
        database.save!

        linked_page = create_linked_page!(database)
        Pundit.authorize(workflow_run.user, database, :update?)
        database.update!(linked_page: linked_page)

        create_default_view!(database)
        properties = create_properties!(database)
        create_rows!(database, properties)

        result_for(database.id)
      end

      private

      attr_reader :workflow_run

      def create_linked_page!(database)
        page = workflow_run.workspace.pages.new(
          title: database.name,
          parent_page: parent_page,
          created_by: workflow_run.user,
          page_kind: "nota"
        )
        Pundit.authorize(workflow_run.user, page, :create?)
        page.save!
        page
      end

      def parent_page
        parent_page_id = workflow_run.input_json["parent_page_id"].to_s.presence
        return if parent_page_id.blank?

        @parent_page ||= Pundit.policy_scope!(workflow_run.user, Page)
                                 .for_workspace(workflow_run.workspace)
                                 .active
                                 .find(parent_page_id)
      end

      def create_default_view!(database)
        view = database.database_views.new(
          workspace: workflow_run.workspace,
          created_by: workflow_run.user,
          name: "Table",
          view_type: :table,
          default: true
        )
        Pundit.authorize(workflow_run.user, view, :create?)
        view.save!
      end

      def create_properties!(database)
        normalized_properties.map do |attributes|
          property = database.db_properties.new(
            workspace: workflow_run.workspace,
            name: attributes.fetch("name"),
            property_type: attributes.fetch("property_type")
          )
          if property.respond_to?(:select_options_list=) && attributes["select_options"].present?
            property.select_options_list = attributes["select_options"]
          end
          Pundit.authorize(workflow_run.user, property, :create?)
          property.save!
          property
        end
      end

      def normalized_properties
        @normalized_properties ||= begin
          properties = Array(workflow_run.input_json["properties"]).map do |raw_property|
            attributes = raw_property.respond_to?(:to_h) ? raw_property.to_h.stringify_keys : { "name" => raw_property.to_s }
            name = attributes["name"].to_s.strip
            raise ArgumentError, "Every database property requires a name" if name.blank?

            property_type = (attributes["property_type"].presence || attributes["type"].presence || "text").to_s
            unless DbProperty.property_types.key?(property_type)
              raise ArgumentError, "Unsupported property type for #{name}: #{property_type}"
            end

            {
              "name" => name,
              "property_type" => property_type,
              "select_options" => Array(attributes["select_options"].presence || attributes["options"]).map(&:to_s)
            }
          end

          duplicate_name = properties.group_by { |property| property.fetch("name").downcase }.find { |_name, matches| matches.many? }&.first
          raise ArgumentError, "Duplicate database property: #{duplicate_name}" if duplicate_name.present?

          properties
        end
      end

      def create_rows!(database, properties)
        properties_by_name = properties.index_by { |property| property.name.to_s.strip.downcase }
        Array(workflow_run.input_json["rows"]).each_with_index do |raw_row, index|
          row_input = raw_row.to_h.stringify_keys
          title = (row_input["title"].presence || row_input["name"].presence || "Row #{index + 1}").to_s.strip
          raise ArgumentError, "Every database row requires a title" if title.blank?

          row = database.db_rows.new(workspace: workflow_run.workspace, title: title)
          Pundit.authorize(workflow_run.user, row, :create?)
          row.save!
          create_cells!(row, row_input["cells"], properties_by_name)
          Pundit.authorize(workflow_run.user, row, :update?)
          row.sync_data_from_cells!
        end
      end

      def create_cells!(row, raw_cells, properties_by_name)
        normalize_cells(raw_cells).each do |cell_input|
          property_name = cell_input.fetch("property").to_s.strip
          property = properties_by_name[property_name.downcase]
          raise ArgumentError, "Unknown database property: #{property_name}" if property.blank?

          cell = row.db_cells.new(
            workspace: workflow_run.workspace,
            db_property: property,
            value_text: cell_input["value"].to_s
          )
          Pundit.authorize(workflow_run.user, cell, :create?)
          cell.save!
        end
      end

      def normalize_cells(raw_cells)
        if raw_cells.is_a?(Hash)
          raw_cells.map { |property, value| { "property" => property, "value" => value } }
        else
          Array(raw_cells).map do |raw_cell|
            cell = raw_cell.to_h.stringify_keys
            raise ArgumentError, "Every cell requires a property name" if cell["property"].to_s.strip.blank?

            cell
          end
        end
      end

      def result_for(database_id)
        database = Pundit.policy_scope!(workflow_run.user, Database)
                         .for_workspace(workflow_run.workspace)
                         .find(database_id)
        properties = database.db_properties.ordered.to_a
        rows = database.db_rows.active.ordered.includes(:linked_page).to_a
        cells = DbCell.where(db_row_id: rows.map(&:id)).order(:created_at).to_a
        serialized = Api::V1::Serializers::DatabaseSerializer.render(database, properties: properties, rows: rows, cells: cells)
        serialized[:linked_page] = Api::V1::Serializers::PageSerializer.render(database.linked_page)

        {
          "target_type" => "Database",
          "target_id" => database.id,
          "title" => database.name,
          "url" => Rails.application.routes.url_helpers.database_path(workspace_slug: workflow_run.workspace.slug, id: database.id),
          "database" => serialized
        }
      end
    end
  end
end
