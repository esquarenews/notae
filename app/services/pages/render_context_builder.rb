module Pages
  class RenderContextBuilder
    Result = Struct.new(
      :active_blocks,
      :blocks_by_parent,
      :block_lookup,
      :indexes,
      :reader_mode,
      :linked_target_pages_by_id,
      keyword_init: true
    )

    def initialize(page:, workspace:, block_scope:, page_scope:)
      @page = page
      @workspace = workspace
      @block_scope = block_scope
      @page_scope = page_scope
    end

    def call
      active_blocks = load_active_blocks

      Result.new(
        active_blocks: active_blocks,
        blocks_by_parent: active_blocks.group_by(&:parent_block_id),
        block_lookup: active_blocks.index_by(&:id),
        indexes: active_blocks.each_with_index.to_h { |block, index| [ block.id, index ] },
        reader_mode: @page.remove_blocks? || @page.locked?,
        linked_target_pages_by_id: linked_target_pages_by_id(active_blocks)
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

    def linked_target_pages_by_id(active_blocks)
      target_page_ids = active_blocks.filter_map do |block|
        Blocks::SplitLinkResolver.target_page_id(content_json: block.content_json)
      end.uniq
      return {} if target_page_ids.empty?

      @page_scope
        .for_workspace(@workspace)
        .where(id: target_page_ids)
        .includes(:linked_database)
        .index_by { |page| page.id.to_s }
    end
  end
end
