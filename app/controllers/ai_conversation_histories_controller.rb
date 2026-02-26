class AiConversationHistoriesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace

  def show
    authorize @workspace, :show?

    @ai_conversations = recent_ai_conversations_for(user: current_user, window: 1.week, limit: 300).to_a
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end
end
