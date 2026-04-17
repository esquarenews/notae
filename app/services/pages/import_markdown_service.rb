require "stringio"

module Pages
  class ImportMarkdownService
    class Error < StandardError; end

    Result = Struct.new(:imported_blocks, :skipped_documents, keyword_init: true)

    DEFAULT_FILENAME = "document.md".freeze

    class << self
      def call(page:, workspace:, user:, markdown:, insert_after_id: nil, filename: DEFAULT_FILENAME)
        new(page:, workspace:, user:, markdown:, insert_after_id:, filename:).call
      end
    end

    def initialize(page:, workspace:, user:, markdown:, insert_after_id:, filename:)
      @page = page
      @workspace = workspace
      @user = user
      @markdown = markdown.to_s
      @insert_after_id = insert_after_id
      @filename = filename.to_s.presence || DEFAULT_FILENAME
      @skipped_documents = []
    end

    def call
      raise Error, "Markdown content is required." if markdown.strip.blank?

      parse_result = Imports::ContentParser.parse(filename: filename, io: StringIO.new(markdown))
      block_payloads = extract_page_block_payloads(parse_result.documents)
      raise Error, "Markdown could not be imported as page content." if block_payloads.empty?

      imported_blocks = Pages::InsertBlocksService.call(
        page: page,
        workspace: workspace,
        user: user,
        blocks: block_payloads,
        insert_after_id: insert_after_id
      )

      Result.new(imported_blocks: imported_blocks, skipped_documents: skipped_documents)
    rescue Imports::ContentParser::UnsupportedFormatError => error
      raise Error, error.message
    end

    private

    attr_reader :page, :workspace, :user, :markdown, :insert_after_id, :filename, :skipped_documents

    def extract_page_block_payloads(documents)
      Array(documents).flat_map do |document|
        if document.target_type.to_s == Imports::ContentParser::TARGET_DATABASE
          skipped_documents << document.title.to_s.presence || "Untitled document"
          next []
        end

        Array(document.blocks).presence || [ default_block_payload ]
      end
    end

    def default_block_payload
      {
        block_type: "paragraph",
        content_json: Block::DEFAULT_CONTENT.deep_dup
      }
    end
  end
end
