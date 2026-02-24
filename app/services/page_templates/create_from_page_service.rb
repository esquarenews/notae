module PageTemplates
  class CreateFromPageService
    class << self
      def call(page:, created_by:, name:)
        blocks = page.blocks.active.order(:position, :created_at).includes(asset_attachment: :blob).to_a
        snapshot_blocks = blocks.map do |block|
          {
            "key" => block.id,
            "parent_key" => block.parent_block_id,
            "block_type" => block.block_type,
            "content_json" => block.content_json,
            "position" => block.position,
            "embed_url" => block.embed_url,
            "attachment_blob_id" => block.asset.attached? ? block.asset.blob_id : nil
          }.compact
        end

        PageTemplate.create!(
          workspace: page.workspace,
          page: page,
          created_by: created_by,
          name: name.to_s.strip.presence || page.title,
          snapshot_json: {
            "page_title" => page.title,
            "blocks" => snapshot_blocks
          }
        )
      end
    end
  end
end
