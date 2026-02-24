module Api
  module V1
    module Serializers
      class PageSerializer
        def self.render_collection(pages)
          pages.map { |page| render(page) }
        end

        def self.render(page)
          {
            id: page.id,
            workspace_id: page.workspace_id,
            parent_page_id: page.parent_page_id,
            title: page.title,
            permission_mode: page.permission_mode,
            archived_at: page.archived_at&.iso8601(6),
            created_by_id: page.created_by_id,
            created_at: page.created_at&.iso8601(6),
            updated_at: page.updated_at&.iso8601(6)
          }
        end
      end
    end
  end
end
