module Imports
  class IngestService
    Result = Struct.new(:imported_pages, :imported_databases, :skipped_files, :errors, keyword_init: true) do
      def imported_count
        imported_page_count + imported_database_count
      end

      def imported_page_count
        imported_pages.count
      end

      def imported_database_count
        imported_databases.count
      end
    end

    def self.call(workspace:, user:, files:)
      new(workspace: workspace, user: user, files: files).call
    end

    def initialize(workspace:, user:, files:)
      @workspace = workspace
      @user = user
      @files = Array(files).reject(&:blank?)
      @imported_pages = []
      @imported_databases = []
      @skipped_files = []
      @errors = []
    end

    def call
      @files.each do |uploaded_file|
        parse_and_import_file(uploaded_file)
      end

      Result.new(
        imported_pages: @imported_pages,
        imported_databases: @imported_databases,
        skipped_files: @skipped_files.uniq,
        errors: @errors
      )
    end

    private

    def parse_and_import_file(uploaded_file)
      parse_result = Imports::ContentParser.parse(filename: uploaded_file.original_filename, io: uploaded_file.tempfile)
      @skipped_files.concat(parse_result.skipped_files)
      parse_result.documents.each do |document|
        import_document(document)
      end
    rescue Imports::ContentParser::UnsupportedFormatError
      @skipped_files << uploaded_file.original_filename
    rescue StandardError => e
      @errors << "Failed to import #{uploaded_file.original_filename}: #{e.message}"
    end

    def import_document(document)
      if document.target_type.to_s == Imports::ContentParser::TARGET_DATABASE
        import_database(document)
      else
        import_page(document)
      end
    end

    def import_page(document)
      page_title = unique_page_title(document.title.to_s.presence || "Imported page")
      page = @workspace.pages.create!(title: page_title, created_by: @user)

      blocks = document.blocks.presence || [ default_block_payload ]
      blocks.each_with_index do |block_payload, index|
        page.blocks.create!(
          workspace: @workspace,
          created_by: @user,
          block_type: block_payload[:block_type].to_s,
          content_json: block_payload[:content_json],
          position: (index + 1) * Block::POSITION_GAP
        )
      end

      @imported_pages << page
    end

    def import_database(document)
      database_name = unique_database_name(document.title.to_s.presence || "Imported grid")
      headers, rows = normalized_csv_table(Array(document.table_rows))

      ActiveRecord::Base.transaction do
        database = @workspace.databases.create!(name: database_name, created_by: @user)
        database.database_views.create!(
          workspace: @workspace,
          created_by: @user,
          name: "Table",
          view_type: :table,
          default: true
        )

        title_column_consumed = consume_title_column?(headers)
        property_headers = title_column_consumed ? headers.drop(1) : headers
        property_columns = title_column_consumed ? (1...headers.length).to_a : (0...headers.length).to_a

        properties = property_columns.each_with_index.map do |column_index, property_index|
          database.db_properties.create!(
            workspace: @workspace,
            name: unique_property_name(property_headers[property_index].presence || "Column #{column_index + 1}", database: database),
            property_type: infer_property_type(rows, column_index: column_index),
            position: (property_index + 1) * DbProperty::POSITION_GAP
          )
        end

        rows.each_with_index do |values, row_index|
          row = database.db_rows.create!(
            title: row_title_for_csv_row(values, row_index: row_index, title_column_consumed: title_column_consumed)
          )

          properties.each_with_index do |property, property_index|
            source_column_index = property_columns[property_index]
            value = values[source_column_index].to_s.strip
            next if value.blank?

            row.db_cells.create!(
              db_property: property,
              value_text: value
            )
          end

          row.sync_data_from_cells!
        end

        @imported_databases << database
      end
    end

    def unique_page_title(base_title)
      title = base_title
      suffix = 2
      while @workspace.pages.exists?(title: title)
        title = "#{base_title} (#{suffix})"
        suffix += 1
      end
      title
    end

    def unique_database_name(base_name)
      title = base_name
      suffix = 2
      while @workspace.databases.exists?(name: title)
        title = "#{base_name} (#{suffix})"
        suffix += 1
      end
      title
    end

    def normalized_csv_table(table_rows)
      normalized_rows = Array(table_rows).map { |row| Array(row).map { |value| value.to_s } }
      return [ [ "Name" ], [] ] if normalized_rows.empty?

      max_width = normalized_rows.map(&:length).max.to_i
      max_width = 1 if max_width <= 0
      normalized_rows = normalized_rows.map { |row| row.fill("", row.length...max_width) }

      headers = normalized_rows.first.map.with_index do |value, index|
        value.to_s.strip.presence || "Column #{index + 1}"
      end
      rows = normalized_rows.drop(1)

      [ headers, rows ]
    end

    def consume_title_column?(headers)
      first_header = Array(headers).first.to_s.strip
      first_header.blank? || first_header.casecmp("name").zero?
    end

    def row_title_for_csv_row(values, row_index:, title_column_consumed:)
      title =
        if title_column_consumed
          values.first.to_s.strip
        else
          values.find { |value| value.to_s.strip.present? }.to_s.strip
        end

      title.presence || "Row #{row_index + 1}"
    end

    def unique_property_name(base_name, database:)
      name = base_name.to_s.strip.presence || "Column"
      existing = database.db_properties.pluck(:name).map { |value| value.to_s.downcase }
      return name unless existing.include?(name.downcase)

      suffix = 2
      loop do
        candidate = "#{name} #{suffix}"
        return candidate unless existing.include?(candidate.downcase)

        suffix += 1
      end
    end

    def infer_property_type(rows, column_index:)
      values = Array(rows).filter_map do |row|
        value = Array(row)[column_index].to_s.strip
        value.presence
      end
      return :text if values.empty?
      return :checkbox if values.all? { |value| boolean_like?(value) }
      return :number if values.all? { |value| number_like?(value) }
      return :date if values.all? { |value| date_like?(value) }

      :text
    end

    def boolean_like?(value)
      normalized = value.to_s.strip.downcase
      DbCell::TRUTHY_VALUES.include?(normalized) || DbCell::FALSY_VALUES.include?(normalized)
    end

    def number_like?(value)
      Float(value)
      true
    rescue ArgumentError, TypeError
      false
    end

    def date_like?(value)
      Date.parse(value)
      true
    rescue ArgumentError, TypeError
      false
    end

    def default_block_payload
      {
        block_type: "paragraph",
        content_json: {
          "type" => "doc",
          "content" => [ { "type" => "paragraph" } ]
        }
      }
    end
  end
end
