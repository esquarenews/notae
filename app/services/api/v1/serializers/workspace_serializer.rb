module Api
  module V1
    module Serializers
      class WorkspaceSerializer
        def self.render_collection(workspaces, user:)
          workspaces.map { |workspace| render(workspace, user:) }
        end

        def self.render(workspace, user:)
          membership = workspace.memberships.find { |candidate| candidate.user_id == user.id } ||
                       workspace.memberships.find_by(user_id: user.id)

          {
            id: workspace.id,
            name: workspace.name,
            slug: workspace.slug,
            role: membership&.role,
            created_at: workspace.created_at&.iso8601(6),
            updated_at: workspace.updated_at&.iso8601(6)
          }
        end
      end
    end
  end
end
