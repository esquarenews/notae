module Blocks
  class RestoreService
    def self.call(block:)
      new(block:).call
    end

    def initialize(block:)
      @block = block
    end

    def call
      Block.transaction do
        shift_conflicting_active_positions!
        ids = block.archiveable_tree_ids
        now = Time.current
        Block.where(id: ids).update_all(archived_at: nil, updated_at: now)
        Block.where(id: ids).find_each { |restored_block| PageLinks::SyncFromBlockService.call(block: restored_block) }
      end
    end

    private

    attr_reader :block

    def shift_conflicting_active_positions!
      Block.active
           .where(page_id: block.page_id, parent_block_id: block.parent_block_id)
           .where("position >= ?", block.position)
           .update_all("position = position + #{Block::POSITION_GAP}")
    end
  end
end
