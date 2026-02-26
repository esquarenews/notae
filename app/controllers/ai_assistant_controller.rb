class AiAssistantController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace

  def create
    authorize @workspace, :show?

    @ai_assistant_prompt = assistant_params[:prompt].to_s.strip
    @ai_assistant_scope = assistant_scope
    @ai_assistant_current_page_id = assistant_params[:current_page_id].presence

    service = Search::AssistantQueryService.new(
      user: current_user,
      workspace: @workspace,
      prompt: @ai_assistant_prompt,
      scope: @ai_assistant_scope,
      current_page_id: @ai_assistant_current_page_id
    )
    @ai_assistant_response = service.call
    @ai_assistant_notice = notice_for(service.unavailable_reason)
    record_ai_conversation!
    @ai_rail_workspace = @workspace
    @ai_rail_current_page_id = @ai_assistant_current_page_id
    @ai_rail_conversations = recent_ai_conversations_for(user: current_user, window: 1.week, limit: 60).to_a.reverse
    @ai_usage_panel = build_ai_usage_panel(user: current_user, workspace: @workspace)
    @ai_conversations = recent_ai_conversations_for(user: current_user, window: 1.week, limit: 300).to_a

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.update("ai_rail_panel", partial: "shared/app_ai_rail"),
          turbo_stream.update(
            "ai_conversation_history_list",
            partial: "ai_conversation_histories/history_list",
            locals: { ai_conversations: @ai_conversations }
          )
        ]
      end
      format.html do
        redirect_back fallback_location: workspace_path(@workspace.slug), notice: @ai_assistant_notice
      end
    end
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def assistant_params
    params.fetch(:ai_assistant, {}).permit(:prompt, :scope, :current_page_id)
  end

  def assistant_scope
    requested_scope = assistant_params[:scope].to_s
    valid_scopes = Search::AssistantQueryService::SCOPE_OPTIONS.map(&:last)
    valid_scopes.include?(requested_scope) ? requested_scope : Search::AssistantQueryService::SCOPE_AUTO
  end

  def notice_for(reason)
    case reason
    when :rate_limited
      "Notae AI is temporarily rate-limited. Try again shortly."
    when :budget_exceeded
      "Notae AI budget reached for today."
    when :no_context
      "Notae AI could not find enough context for that request."
    when :provider_error
      "Notae AI request failed. Please retry."
    when :missing_api_key
      "Configure an OpenAI key in Settings > Connections first."
    when :missing_prompt
      "Enter a prompt to ask Notae AI."
    else
      nil
    end
  end

  def record_ai_conversation!
    return if @ai_assistant_prompt.blank?

    answer = @ai_assistant_response&.answer.presence || @ai_assistant_notice.presence
    return if answer.blank?

    sources = Array(@ai_assistant_response&.sources).map do |source|
      source.slice(:index, :title, :kind, :url, :workspace_name)
    end
    page_id = policy_scope(Page).active.where(workspace_id: @workspace.id).find_by(id: @ai_assistant_current_page_id)&.id

    AiConversation.create!(
      user: current_user,
      workspace: @workspace,
      page_id: page_id,
      scope: @ai_assistant_response&.scope.presence || @ai_assistant_scope,
      status: @ai_assistant_response.present? ? AiConversation::STATUS_SUCCESS : AiConversation::STATUS_NOTICE,
      prompt: @ai_assistant_prompt,
      answer: answer,
      sources: sources
    )
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn("AI conversation persist failed for workspace=#{@workspace.id}: #{e.message}")
  end
end
