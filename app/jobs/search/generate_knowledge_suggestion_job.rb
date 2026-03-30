module Search
  class GenerateKnowledgeSuggestionJob < ApplicationJob
    queue_as :default

    def perform(user_id, workspace_id, kind)
      user = User.find_by(id: user_id)
      workspace = Workspace.find_by(id: workspace_id)
      return if user.blank? || workspace.blank?

      Search::PersistKnowledgeSuggestionService.new(
        user: user,
        workspace: workspace,
        kind: kind
      ).call
    ensure
      if user.present? && workspace.present?
        Search::KnowledgeSuggestionGenerationTracker.clear!(user: user, workspace: workspace, kind: kind)
      end
    end
  end
end
