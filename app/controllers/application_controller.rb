class ApplicationController < ActionController::Base
  include Pundit::Authorization

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :set_paper_trail_whodunnit
  before_action :set_unread_notifications_count
  before_action :set_ai_rail_context
  before_action :set_ai_rail_conversations
  before_action :set_ai_rail_usage_panel
  before_action :ensure_realtime_channel_loaded
  around_action :use_user_time_zone
  after_action :verify_pundit_authorization, unless: :devise_controller?

  rescue_from Pundit::NotAuthorizedError, with: :handle_not_authorized

  private

  def verify_pundit_authorization
    action_name == "index" ? verify_policy_scoped : verify_authorized
  end

  def handle_not_authorized
    redirect_back fallback_location: root_path, alert: "You are not authorized to perform this action."
  end

  def set_unread_notifications_count
    @unread_notifications_count =
      if user_signed_in?
        policy_scope(Notification).unread.count
      else
        0
      end
  end

  def set_ai_rail_context
    return unless user_signed_in?

    @ai_rail_workspace = if params[:workspace_slug].present?
      policy_scope(Workspace).find_by(slug: params[:workspace_slug])
    end
    @ai_rail_workspace ||= policy_scope(Workspace).order(updated_at: :desc).first
    @ai_rail_current_page_id = params[:controller] == "pages" && params[:action] == "show" ? params[:id] : nil
  end

  def set_ai_rail_usage_panel
    return unless user_signed_in?
    return if @ai_rail_workspace.blank?

    @ai_usage_panel = build_ai_usage_panel(user: current_user, workspace: @ai_rail_workspace)
  end

  def set_ai_rail_conversations
    return unless user_signed_in?

    @ai_rail_conversations = recent_ai_conversations_for(user: current_user, window: 1.week, limit: 60).to_a.reverse
  end

  def recent_ai_conversations_for(user:, window: 1.week, limit: 60)
    workspace_ids = policy_scope(Workspace).select(:id)
    AiConversation
      .for_user(user)
      .where(workspace_id: workspace_ids)
      .where(created_at: window.ago..Time.current)
      .includes(:workspace, :page)
      .recent_first
      .limit(limit)
  end

  def build_ai_usage_panel(user:, workspace:)
    day_end = Time.current
    day_start = day_end.beginning_of_day
    usage_scope = AiUsageLog.for_user_and_workspace(user: user, workspace: workspace).for_day(day_start, day_end)

    prompt_tokens, completion_tokens, total_tokens, estimated_cost_usd, request_count = usage_scope.pick(
      Arel.sql("COALESCE(SUM(prompt_tokens), 0)"),
      Arel.sql("COALESCE(SUM(completion_tokens), 0)"),
      Arel.sql("COALESCE(SUM(total_tokens), 0)"),
      Arel.sql("COALESCE(SUM(estimated_cost_usd), 0)"),
      Arel.sql("COUNT(*)")
    )

    daily_budget_usd = user.resolved_ai_search_daily_budget_usd
    spent_today = estimated_cost_usd.to_f
    budget_remaining = [ daily_budget_usd - spent_today, 0.0 ].max

    {
      day_label: day_end.strftime("%b %-d"),
      prompt_tokens: prompt_tokens.to_i,
      completion_tokens: completion_tokens.to_i,
      total_tokens: total_tokens.to_i,
      estimated_cost_usd: spent_today,
      request_count: request_count.to_i,
      budget_status: Search::AiBudgetGuard.within_daily_budget?(user: user, workspace: workspace),
      daily_budget_usd: daily_budget_usd,
      budget_remaining_usd: budget_remaining,
      semantic_rate_limit_per_minute: user.resolved_ai_search_semantic_rate_limit_per_minute,
      answer_rate_limit_per_minute: user.resolved_ai_search_answer_rate_limit_per_minute,
      rate_limit_window_seconds: Rails.application.config.x.ai_search.rate_limit_window_seconds.to_i
    }
  end

  def ensure_realtime_channel_loaded
    return if defined?(::PageChannel)

    load Rails.root.join("app/channels/application_cable/channel.rb").to_s unless defined?(::ApplicationCable::Channel)
    load Rails.root.join("app/channels/page_channel.rb").to_s
  end

  def use_user_time_zone(&block)
    return yield unless user_signed_in?

    zone_name = current_user.time_zone.presence
    zone = zone_name && ActiveSupport::TimeZone[zone_name]
    return yield unless zone

    Time.use_zone(zone, &block)
  end
end
