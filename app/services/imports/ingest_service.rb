module Imports
  class IngestService
    Result = Struct.new(:imported_pages, :skipped_files, :errors, keyword_init: true) do
      def imported_count
        imported_pages.count
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
      @skipped_files = []
      @errors = []
    end

    def call
      @files.each do |uploaded_file|
        parse_and_import_file(uploaded_file)
      end

      Result.new(imported_pages: @imported_pages, skipped_files: @skipped_files.uniq, errors: @errors)
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

    def unique_page_title(base_title)
      title = base_title
      suffix = 2
      while @workspace.pages.exists?(title: title)
        title = "#{base_title} (#{suffix})"
        suffix += 1
      end
      title
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
