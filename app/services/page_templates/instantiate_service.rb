module PageTemplates
  class InstantiateService
    class << self
      def call(template:, workspace:, created_by:, title: nil, parent_page_id: nil)
        ActiveRecord::Base.transaction do
          page = Page.create!(
            workspace: workspace,
            created_by: created_by,
            parent_page_id: parent_page_id,
            title: title.to_s.strip.presence || template.snapshot_json["page_title"].presence || template.name
          )
          instantiate_blocks!(template: template, page: page, created_by: created_by, workspace: workspace)
          page
        end
      end

      private

      def instantiate_blocks!(template:, page:, created_by:, workspace:)
        block_mapping = {}
        Array(template.snapshot_json["blocks"]).each do |snapshot_block|
          parent_key = snapshot_block["parent_key"].to_s
          parent_id = parent_key.present? ? block_mapping[parent_key] : nil

          block = page.blocks.create!(
            workspace: workspace,
            created_by: created_by,
            parent_block_id: parent_id,
            block_type: snapshot_block["block_type"].presence || "paragraph",
            content_json: snapshot_block["content_json"].presence || Block::DEFAULT_CONTENT.deep_dup,
            position: snapshot_block["position"],
            embed_url: snapshot_block["embed_url"]
          )

          blob_id = snapshot_block["attachment_blob_id"]
          if blob_id.present?
            blob = ActiveStorage::Blob.find_by(id: blob_id)
            block.asset.attach(blob) if blob.present?
          end

          block_mapping[snapshot_block["key"].to_s] = block.id
        end
      end
    end
  end
end
