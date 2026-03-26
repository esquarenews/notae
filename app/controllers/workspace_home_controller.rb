class WorkspaceHomeController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace

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
    return suggestion if suggestion.present?

    return unless current_user.openai_api_key_configured?

    existing_for_today = policy_scope(KnowledgeSuggestion)
                         .for_workspace(@workspace)
                         .daily_summaries
                         .find_by(generated_for_date: Date.current)
    return nil if existing_for_today.present?

    Search::PersistKnowledgeSuggestionService.ensure_daily_summary!(user: current_user, workspace: @workspace)
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

    current_active_suggestion_for(@workspace)
  end

  def redirect_to_last_visited_page
    last_page_id = session.dig("notae_last_page_visits", @workspace.id.to_s)
    return unless last_page_id

    last_page = policy_scope(Page).for_workspace(@workspace).active.find_by(id: last_page_id)
    return unless last_page

    redirect_to page_path(workspace_slug: @workspace.slug, id: last_page.id)
  end
end
