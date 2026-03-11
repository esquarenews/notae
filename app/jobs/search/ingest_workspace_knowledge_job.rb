module Search
  class IngestWorkspaceKnowledgeJob < ApplicationJob
    queue_as :default

    def perform(workspace_id, requested_by_id)
      workspace = Workspace.find_by(id: workspace_id)
      requested_by = User.find_by(id: requested_by_id)
      return if workspace.blank? || requested_by.blank?

      Search::WorkspaceIngestionService.new(workspace: workspace, requested_by: requested_by).call
    end
  end
end
