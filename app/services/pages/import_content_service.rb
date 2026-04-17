module Pages
  class ImportContentService
    TEXT_IMPORT_EXTENSIONS = (Imports::ContentParser::SUPPORTED_EXTENSIONS - %w[.csv .zip]).freeze
    MEDIA_CONTENT_PREFIXES = %w[image/ video/ audio/].freeze

    Result = Struct.new(:imported_blocks, :skipped_files, :errors, keyword_init: true) do
      def imported_count
        imported_blocks.size
      end

      def skipped_message
        return nil if skipped_files.blank?

        "Skipped #{skipped_files.join(', ')}."
      end

      def error_message
        return nil if errors.blank?

        errors.join(" ")
      end
    end

    def self.call(page:, workspace:, user:, files:, insert_after_id:)
      new(page:, workspace:, user:, files:, insert_after_id:).call
    end

    def initialize(page:, workspace:, user:, files:, insert_after_id:)
      @page = page
      @workspace = workspace
      @user = user
      @files = Array(files).reject(&:blank?)
      @insert_after_block = page.blocks.active.find_by(id: insert_after_id)
      @imported_blocks = []
      @skipped_files = []
      @errors = []
      @target_parent = @insert_after_block&.parent_block
      @target_parent_id = @target_parent&.id
      @next_index = initial_target_index
    end

    def call
      files.each do |uploaded_file|
        import_uploaded_file(uploaded_file)
      end

      Result.new(
        imported_blocks: imported_blocks,
        skipped_files: skipped_files,
        errors: errors
      )
    end

    private

    attr_reader :page, :workspace, :user, :files, :insert_after_block, :imported_blocks, :skipped_files, :errors, :target_parent, :target_parent_id
    attr_accessor :next_index

    def initial_target_index
      siblings = ordered_target_siblings
      return siblings.size if insert_after_block.blank?

      sibling_index = siblings.index { |block| block.id == insert_after_block.id }
      sibling_index ? sibling_index + 1 : siblings.size
    end

    def ordered_target_siblings
      page.blocks.active.where(parent_block_id: target_parent_id).ordered.to_a
    end

    def import_uploaded_file(uploaded_file)
      if text_import?(uploaded_file)
        import_document_file(uploaded_file)
      elsif media_import?(uploaded_file)
        import_media_file(uploaded_file)
      else
        errors << unsupported_message_for(uploaded_file)
      end
    rescue Imports::ContentParser::UnsupportedFormatError
      errors << unsupported_message_for(uploaded_file)
    rescue StandardError => error
      errors << "Failed to import #{uploaded_file.original_filename}: #{error.message}"
    end

    def text_import?(uploaded_file)
      TEXT_IMPORT_EXTENSIONS.include?(File.extname(uploaded_file.original_filename.to_s).downcase)
    end

    def media_import?(uploaded_file)
      MEDIA_CONTENT_PREFIXES.any? { |prefix| uploaded_file.content_type.to_s.start_with?(prefix) }
    end

    def unsupported_message_for(uploaded_file)
      "Unsupported file for page import: #{uploaded_file.original_filename}. Use Settings → Import for CSV or ZIP imports."
    end

    def import_document_file(uploaded_file)
      parse_result = Imports::ContentParser.parse(filename: uploaded_file.original_filename, io: uploaded_file.tempfile)
      skipped_files.concat(parse_result.skipped_files)

      parse_result.documents.each do |document|
        if document.target_type.to_s == Imports::ContentParser::TARGET_DATABASE
          errors << unsupported_message_for(uploaded_file)
          next
        end

        blocks = document.blocks.presence || [ default_block_payload ]
        inserted_blocks = Pages::InsertBlocksService.call(
          page: page,
          workspace: workspace,
          user: user,
          blocks: blocks,
          target_parent_id: target_parent_id,
          target_index: next_index
        )
        imported_blocks.concat(inserted_blocks)
        self.next_index += inserted_blocks.size
      end
    end

    def import_media_file(uploaded_file)
      block = Pages::InsertBlocksService.call(
        page: page,
        workspace: workspace,
        user: user,
        blocks: [
          {
            block_type: block_type_for_media(uploaded_file),
            content_json: Block::DEFAULT_CONTENT.deep_dup
          }
        ],
        target_parent_id: target_parent_id,
        target_index: next_index
      ).first
      self.next_index += 1
      imported_blocks << block
      block.asset.attach(uploaded_file)
      block.touch
    end

    def block_type_for_media(uploaded_file)
      content_type = uploaded_file.content_type.to_s
      return "image" if content_type.start_with?("image/")
      return "video" if content_type.start_with?("video/")

      "file"
    end

    def default_block_payload
      {
        block_type: "paragraph",
        content_json: Block::DEFAULT_CONTENT.deep_dup
      }
    end
  end
end
