class AiAssistantController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace

  def create
    authorize @workspace, :show?

    @ai_assistant_prompt = assistant_params[:prompt].to_s
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
    @ai_rail_workspace = @workspace
    @ai_rail_current_page_id = @ai_assistant_current_page_id

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.update(
          "ai_rail_panel",
          partial: "shared/app_ai_rail"
        )
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
    else
      nil
    end
  end
end
