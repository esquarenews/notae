module PageLinks
  class SyncFromBlockService
    WIKI_LINK_PATTERN = /\[\[([^\[\]]+)\]\]/
    PAGE_PATH_PATTERN = %r{/w/[^/]+/pages/([0-9a-f-]{36})}i
    SPLIT_PAGE_PATH_PATTERN = %r{/w/[^/]+/pages/[0-9a-f-]{36}[^"']*?[?&]split_page_id=([0-9a-f-]{36})}i

    def self.call(block:)
      new(block:).call
    end

    def initialize(block:)
      @block = block
    end

    def call
      PageLink.where(source_block_id: block.id).delete_all
      return if block.archived_at.present?

      detect_target_page_ids.each do |target_page_id|
        next if target_page_id == block.page_id

        PageLink.find_or_create_by!(
          workspace_id: block.workspace_id,
          source_page_id: block.page_id,
          target_page_id: target_page_id,
          source_block_id: block.id
        )
      end
    end

    private

    attr_reader :block

    def detect_target_page_ids
      ids = []

      linked_titles = block.search_text.scan(WIKI_LINK_PATTERN).flatten.map(&:strip).reject(&:blank?)
      if linked_titles.any?
        ids.concat(
          block.workspace.pages.where("LOWER(title) IN (?)", linked_titles.map(&:downcase)).pluck(:id)
        )
      end

      explicit_ids = block.content_json.to_json.scan(PAGE_PATH_PATTERN).flatten
      if explicit_ids.any?
        ids.concat(block.workspace.pages.where(id: explicit_ids).pluck(:id))
      end

      split_target_ids = block.content_json.to_json.scan(SPLIT_PAGE_PATH_PATTERN).flatten
      if split_target_ids.any?
        ids.concat(block.workspace.pages.where(id: split_target_ids).pluck(:id))
      end

      ids.uniq
    end
  end
end
