module Pages
  class DuplicateService
    class << self
      def call(page:, created_by:, title: nil)
        ActiveRecord::Base.transaction do
          duplicate_page = Page.create!(
            workspace: page.workspace,
            created_by: created_by,
            parent_page_id: page.parent_page_id,
            title: duplicate_title(page, title),
            permission_mode: page.permission_mode,
            icon: page.icon,
            cover_preset_key: page.cover_preset_key,
            cover_focal_y: page.cover_focal_y,
            font_style: page.font_style,
            small_text: page.small_text,
            full_width: page.full_width,
            locked: false,
            suggest_edits: page.suggest_edits
          )

          if page.cover_image.attached?
            duplicate_page.cover_image.attach(page.cover_image.blob)
          end

          duplicate_blocks!(source_page: page, target_page: duplicate_page, created_by: created_by)
          duplicate_page
        end
      end

      private

      def duplicate_title(page, title)
        supplied_title = title.to_s.strip
        return supplied_title if supplied_title.present?

        "#{page.title} (copy)"
      end

      def duplicate_blocks!(source_page:, target_page:, created_by:)
        block_id_mapping = {}
        ordered_blocks = ordered_block_tree(source_page)

        ordered_blocks.each do |source_block|
          parent_id = source_block.parent_block_id.present? ? block_id_mapping[source_block.parent_block_id] : nil

          duplicated_block = target_page.blocks.create!(
            workspace: target_page.workspace,
            created_by: created_by,
            parent_block_id: parent_id,
            block_type: source_block.block_type,
            content_json: source_block.content_json,
            position: source_block.position,
            embed_url: source_block.embed_url,
            archived_at: nil
          )

          if source_block.asset.attached?
            duplicated_block.asset.attach(source_block.asset.blob)
          end

          block_id_mapping[source_block.id] = duplicated_block.id
        end
      end

      def ordered_block_tree(page)
        blocks_by_parent = page.blocks.active.order(:position, :created_at).to_a.group_by(&:parent_block_id)
        ordered = []
        queue = Array(blocks_by_parent[nil]).dup

        until queue.empty?
          block = queue.shift
          ordered << block
          queue.concat(Array(blocks_by_parent[block.id]))
        end

        ordered
      end
    end
  end
end
