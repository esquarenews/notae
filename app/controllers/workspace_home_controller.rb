class WorkspaceHomeController < ApplicationController
  include RequestPerformanceInstrumentation

  before_action :authenticate_user!
  before_action :set_workspace
  track_request_performance_for :show

  def show
    authorize @workspace, :show?
    redirect_to_last_visited_page and return if open_last_visited_page?

    @time_greeting = greeting_for(Time.zone.now)
    @hero_banner_period = banner_period_for(Time.zone.now)
    @invitation = Invitation.new
    @new_page = Page.new
    @new_database = Database.new
    @memberships = policy_scope(Membership).where(workspace_id: @workspace.id).includes(:user).order(:created_at)
    @recent_pages = policy_scope(Page)
                    .for_workspace(@workspace)
                    .active
                    .includes(cover_image_attachment: :blob)
                    .order(updated_at: :desc)
                    .limit(3)
                    .to_a
    @recent_databases = policy_scope(Database).for_workspace(@workspace).active.order(updated_at: :desc).limit(3).to_a
    @knowledge_task_databases = knowledge_task_databases_for(@workspace)
    @daily_knowledge_suggestion = resolve_daily_knowledge_suggestion
    @active_proactive_knowledge_suggestion = resolve_active_proactive_knowledge_suggestion
    @pending_agent_actions = resolve_pending_agent_actions
    @can_invite = policy(Invitation.new(workspace: @workspace)).create?
    @can_manage_memberships = @memberships.any? { |membership| policy(membership).update? }
    @audit_events = policy_scope(AuditEvent)
                      .where(workspace_id: @workspace.id)
                      .includes(:actor)
                      .recent_first
                      .limit(15)
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def greeting_for(time)
    hour = time.hour
    return "Good morning" if hour < 12
    return "Good afternoon" if hour < 18

    "Good evening"
  end

  def banner_period_for(time)
    hour = time.hour
    return "morning" if hour < 12
    return "afternoon" if hour < 18

    "evening"
  end

  def open_last_visited_page?
    return false if ActiveModel::Type::Boolean.new.cast(params[:show_home])

    current_user.open_on_start_preference == "last_visited_page"
  end

  def resolve_daily_knowledge_suggestion
    return unless data_source_available?("knowledge_suggestions")

    suggestion = policy_scope(KnowledgeSuggestion)
                 .for_workspace(@workspace)
                 .daily_summaries
                 .active
                 .find_by(generated_for_date: Date.current)
    if suggestion.present?
      clear_knowledge_suggestion_generation_pending!(@workspace, kind: KnowledgeSuggestion::KIND_DAILY_SUMMARY)
      @daily_knowledge_suggestion_pending = false
      return suggestion
    end

    return unless current_user.openai_api_key_configured?

    existing_for_today = policy_scope(KnowledgeSuggestion)
                         .for_workspace(@workspace)
                         .daily_summaries
                         .find_by(generated_for_date: Date.current)
    return nil if existing_for_today.present?

    @daily_knowledge_suggestion_pending = knowledge_suggestion_generation_pending?(
      @workspace,
      kind: KnowledgeSuggestion::KIND_DAILY_SUMMARY
    )
    return nil if @daily_knowledge_suggestion_pending
    return nil unless knowledge_suggestion_generation_context_available?(
      @workspace,
      kind: KnowledgeSuggestion::KIND_DAILY_SUMMARY
    )

    @daily_knowledge_suggestion_pending =
      queue_knowledge_suggestion_generation!(@workspace, kind: KnowledgeSuggestion::KIND_DAILY_SUMMARY)
    nil
  end

  def resolve_pending_agent_actions
    return [] unless data_source_available?("agent_actions")

    with_optional_schema_fallback(default: [], feature: "agent action drafts") do
      policy_scope(AgentAction)
        .for_workspace(@workspace)
        .pending
        .recent_first
        .limit(4)
        .to_a
    end
  end

  def resolve_active_proactive_knowledge_suggestion
    return unless data_source_available?("knowledge_suggestions")

    suggestion = current_active_suggestion_for(@workspace)
    if suggestion.present?
      clear_knowledge_suggestion_generation_pending!(@workspace, kind: KnowledgeSuggestion::KIND_PROACTIVE)
      @active_proactive_knowledge_suggestion_pending = false
      return suggestion
    end

    @active_proactive_knowledge_suggestion_pending = knowledge_suggestion_generation_pending?(
      @workspace,
      kind: KnowledgeSuggestion::KIND_PROACTIVE
    )
    return nil unless current_user.openai_api_key_configured?
    return nil unless should_generate_proactive_knowledge_suggestion?
    return nil if @active_proactive_knowledge_suggestion_pending
    return nil if proactive_knowledge_suggestion_recently_checked?(@workspace)
    return nil unless knowledge_suggestion_generation_context_available?(
      @workspace,
      kind: KnowledgeSuggestion::KIND_PROACTIVE
    )

    mark_proactive_knowledge_suggestion_checked!(@workspace)
    @active_proactive_knowledge_suggestion_pending =
      queue_knowledge_suggestion_generation!(@workspace, kind: KnowledgeSuggestion::KIND_PROACTIVE)
    nil
  end

  def redirect_to_last_visited_page
    last_page_id = last_page_visit_store[@workspace.id.to_s]
    return unless last_page_id

    last_page = policy_scope(Page).for_workspace(@workspace).active.find_by(id: last_page_id)
    return unless last_page

    redirect_to page_path(workspace_slug: @workspace.slug, id: last_page.id)
  end
end
