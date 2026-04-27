module Pages
  class RenderContextBuilder
    Result = Struct.new(
      :active_blocks,
      :blocks_by_parent,
      :block_lookup,
      :indexes,
      :reader_mode,
      keyword_init: true
    )

    def initialize(page:, block_scope:)
      @page = page
      @block_scope = block_scope
    end

    def call
      active_blocks = load_active_blocks

      Result.new(
        active_blocks: active_blocks,
        blocks_by_parent: active_blocks.group_by(&:parent_block_id),
        block_lookup: active_blocks.index_by(&:id),
        indexes: active_blocks.each_with_index.to_h { |block, index| [ block.id, index ] },
        reader_mode: @page.remove_blocks? || @page.locked?
      )
    end

    private

    def load_active_blocks
      @block_scope
        .for_page(@page)
        .active
        .ordered
        .with_attached_asset
        .to_a
    end
  end
end
