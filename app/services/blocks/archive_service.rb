module Blocks
  class ArchiveService
    def self.call(block:)
      new(block:).call
    end

    def initialize(block:)
      @block = block
    end

    def call
      ids = block.archiveable_tree_ids
      now = Time.current
      Block.where(id: ids).update_all(archived_at: now, updated_at: now)
      PageLink.where(source_block_id: ids).delete_all
    end

    private

    attr_reader :block
  end
end
