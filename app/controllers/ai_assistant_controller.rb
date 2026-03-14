class AiAssistantController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace

  def create
    authorize @workspace, :show?

    @ai_assistant_prompt = assistant_params[:prompt].to_s.strip
    @ai_assistant_scope = assistant_scope
    @ai_assistant_intent = assistant_intent
    @ai_assistant_current_page_id = assistant_params[:current_page_id].presence
    @ai_assistant_target_block_id = target_block&.id

    service = Search::AssistantQueryService.new(
      user: current_user,
      workspace: @workspace,
      prompt: @ai_assistant_prompt,
      scope: @ai_assistant_scope,
      current_page_id: @ai_assistant_current_page_id,
      intent: @ai_assistant_intent,
      target_block: target_block
    )
    @ai_assistant_response = call_assistant_service(service)
    @ai_assistant_notice = notice_for(@ai_assistant_error_reason || service.unavailable_reason)
    @ai_insert_payload = insert_payload_for(@ai_assistant_response, target_block: target_block)
    record_ai_conversation!
    @ai_rail_workspace = @workspace
    @ai_rail_current_page_id = @ai_assistant_current_page_id
    @ai_rail_conversations = recent_ai_conversations_for(
      user: current_user,
      window: 1.week,
      limit: ai_rail_conversation_limit
    ).to_a.reverse
    @ai_usage_panel = build_ai_usage_panel(user: current_user, workspace: @workspace)
    @ai_conversations = recent_ai_conversations_for(user: current_user, window: 1.week, limit: 300).to_a

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace("ai_rail_panel", partial: "shared/app_ai_rail_panel"),
          turbo_stream.update(
            "ai_conversation_history_list",
            partial: "ai_conversation_histories/history_list",
            locals: { ai_conversations: @ai_conversations }
          )
        ]
      end
      format.html do
        if turbo_frame_request?
          render partial: "shared/app_ai_rail_panel"
        else
          redirect_back fallback_location: workspace_path(@workspace.slug), notice: @ai_assistant_notice
        end
      end
    end
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def assistant_params
    params.fetch(:ai_assistant, {}).permit(:prompt, :scope, :current_page_id, :intent, :target_block_id)
  end

  def assistant_scope
    requested_scope = assistant_params[:scope].to_s
    valid_scopes = Search::AssistantQueryService::SCOPE_OPTIONS.map(&:last)
    valid_scopes.include?(requested_scope) ? requested_scope : Search::AssistantQueryService::SCOPE_AUTO
  end

  def assistant_intent
    requested_intent = assistant_params[:intent].to_s
    return nil if requested_intent.blank?

    Search::AssistantQueryService::INTENT_OPTIONS.include?(requested_intent) ? requested_intent : nil
  end

  def target_block
    return @target_block if defined?(@target_block)
    block_id = assistant_params[:target_block_id].presence
    return @target_block = nil if block_id.blank?

    @target_block = policy_scope(Block).for_workspace(@workspace).active.find_by(id: block_id)
  end

  def call_assistant_service(service)
    service.call
  rescue StandardError => e
    @ai_assistant_error_reason = :provider_error
    Rails.logger.error(
      "AI assistant query crashed for workspace=#{@workspace.id} user=#{current_user.id} " \
      "#{e.class}: #{e.message}\n#{Array(e.backtrace).first(20).join("\n")}"
    )
    nil
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
    when :unsupported_draft_request
      "Notae AI can draft emails, GitHub comments, task tickets, and calendar holds."
    when :draft_generation_failed, :draft_validation_failed
      "Notae AI could not turn that into a valid draft. Add recipients, references, or timing and retry."
    else
      nil
    end
  end

  def insert_payload_for(response, target_block:)
    return nil if response.blank?
    return nil unless response.auto_insert

    text = response.answer.to_s.strip
    return nil if text.blank?

    {
      text: text,
      intent: response.intent,
      target_block_id: target_block&.id
    }
  end

  def record_ai_conversation!
    return if @ai_assistant_prompt.blank?

    answer = @ai_assistant_response&.answer.presence || @ai_assistant_notice.presence
    return if answer.blank?

    sources = Array(@ai_assistant_response&.sources).filter_map do |source|
      normalized_source = source.respond_to?(:with_indifferent_access) ? source.with_indifferent_access : source
      safe_url = sanitized_source_url(normalized_source[:url])
      next if safe_url.blank?

      {
        index: normalized_source[:index],
        title: normalized_source[:title],
        kind: normalized_source[:kind],
        url: safe_url,
        workspace_name: normalized_source[:workspace_name]
      }
    end
    page_id = policy_scope(Page).active.where(workspace_id: @workspace.id).find_by(id: @ai_assistant_current_page_id)&.id

    conversation_attributes = {
      user: current_user,
      workspace: @workspace,
      page_id: page_id,
      scope: @ai_assistant_response&.scope.presence || @ai_assistant_scope,
      status: ai_conversation_status_for_response,
      prompt: @ai_assistant_prompt,
      answer: answer,
      sources: sources
    }
    if AiConversation.column_names.include?("model")
      conversation_attributes[:model] = @ai_assistant_response&.model.presence || "unknown"
    end

    AiConversation.create!(
      conversation_attributes
    )
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn("AI conversation persist failed for workspace=#{@workspace.id}: #{e.message}")
  end

  def ai_conversation_status_for_response
    return AiConversation::STATUS_NOTICE if @ai_assistant_response.blank?
    return AiConversation::STATUS_SUGGESTION if @ai_assistant_response.agent_action.present?

    AiConversation::STATUS_SUCCESS
  end

  def sanitized_source_url(raw_url)
    value = raw_url.to_s.strip
    return nil if value.blank?

    if value.start_with?("/")
      return nil if value.start_with?("//")

      parsed = URI.parse(value)
      return nil if parsed.scheme.present? || parsed.host.present?

      return value
    end

    parsed = URI.parse(value)
    return nil unless %w[http https].include?(parsed.scheme)
    return nil if parsed.host.blank?

    value
  rescue URI::InvalidURIError
    nil
  end
end
