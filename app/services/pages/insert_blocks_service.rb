module Pages
  class InsertBlocksService
    class Error < StandardError; end

    class << self
      def call(page:, workspace:, user:, blocks:, insert_after_id: nil, target_parent_id: nil, target_index: nil)
        new(page:, workspace:, user:, blocks:, insert_after_id:, target_parent_id:, target_index:).call
      end
    end

    def initialize(page:, workspace:, user:, blocks:, insert_after_id:, target_parent_id:, target_index:)
      @page = page
      @workspace = workspace
      @user = user
      @blocks = Array(blocks).map { |block| normalize_block_payload(block) }
      @insert_after_block = target_index.present? ? nil : page.blocks.active.find_by(id: insert_after_id)
      @imported_blocks = []
      @target_parent_id = target_parent_id.presence || @insert_after_block&.parent_block_id
      @target_parent = @target_parent_id.present? ? page.blocks.active.find_by(id: @target_parent_id) : @insert_after_block&.parent_block
      @next_index = target_index.presence || initial_target_index
    end

    def call
      blocks.each do |block_payload|
        imported_blocks << insert_block!(block_payload)
      end

      imported_blocks
    end

    private

    attr_reader :page, :workspace, :user, :blocks, :insert_after_block, :imported_blocks, :target_parent, :target_parent_id
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

    def normalize_block_payload(block_payload)
      payload = block_payload.respond_to?(:deep_symbolize_keys) ? block_payload.deep_symbolize_keys : block_payload.to_h.deep_symbolize_keys
      block_type = payload[:block_type].to_s.strip
      content_json = payload[:content_json]

      raise Error, "Block type is required" if block_type.blank?
      raise Error, "Block content is required" if content_json.blank?

      {
        block_type: block_type,
        content_json: content_json
      }
    end

    def insert_block!(block_payload)
      block = page.blocks.create!(
        workspace: workspace,
        created_by: user,
        parent_block: target_parent,
        block_type: block_payload.fetch(:block_type),
        content_json: block_payload.fetch(:content_json)
      )

      Blocks::ReorderService.call(
        block: block,
        target_parent_id: target_parent_id,
        target_index: next_index
      )

      self.next_index += 1
      block
    end
  end
end
