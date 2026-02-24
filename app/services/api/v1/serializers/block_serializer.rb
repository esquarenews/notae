module Api
  module V1
    module Serializers
      class BlockSerializer
        def self.render_collection(blocks)
          blocks.map { |block| render(block) }
        end

        def self.render(block)
          {
            id: block.id,
            workspace_id: block.workspace_id,
            page_id: block.page_id,
            parent_block_id: block.parent_block_id,
            block_type: block.block_type,
            content_json: block.content_json,
            embed_url: block.embed_url,
            position: block.position,
            archived_at: block.archived_at&.iso8601(6),
            created_by_id: block.created_by_id,
            has_asset: block.asset.attached?,
            asset: asset_payload(block),
            created_at: block.created_at&.iso8601(6),
            updated_at: block.updated_at&.iso8601(6)
          }
        end

        def self.asset_payload(block)
          return nil unless block.asset.attached?

          {
            filename: block.asset.filename.to_s,
            content_type: block.asset.content_type,
            byte_size: block.asset.byte_size
          }
        end
      end
    end
  end
end
