module Api
  module V1
    module Knowledge
      class IngestionsController < BaseController
        before_action :set_workspace!

        def create
          Search::IngestWorkspaceKnowledgeJob.perform_later(workspace.id, current_user.id)

          render json: {
            data: {
              enqueued: true,
              workspace_id: workspace.id,
              workspace_slug: workspace.slug
            }
          }, status: :accepted
        rescue StandardError => error
          render_error(code: "enqueue_failed", message: error.message, status: :service_unavailable)
        end
      end
    end
  end
end
