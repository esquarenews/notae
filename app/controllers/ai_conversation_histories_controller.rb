class AiConversationHistoriesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace

  def show
    authorize @workspace, :show?

    @ai_conversations = recent_ai_conversations_for(user: current_user, window: 1.week, limit: 300).to_a
    include_target_conversation!
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def include_target_conversation!
    conversation_id = params[:conversation_id].to_s.strip
    return if conversation_id.blank?
    return if @ai_conversations.any? { |conversation| conversation.id == conversation_id }

    conversation = AiConversation
                   .for_user(current_user)
                   .find_by(id: conversation_id)
    return if conversation.blank?

    @ai_conversations.unshift(conversation)
  end
end
