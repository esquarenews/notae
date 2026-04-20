require "uri"
require Rails.root.join("lib/notae/session_diagnostics")
require Rails.root.join("lib/notae/session_event_store")
require Rails.root.join("lib/notae/session_state_pruner")

class ApplicationController < ActionController::Base
  include Pundit::Authorization

  AI_RAIL_CONVERSATION_LIMIT = 20
  AI_AGENT_UPDATE_LIMIT = 8
  AI_AGENT_TRIGGER_SOURCES = %w[ai_assistant automation_agent].freeze
  AI_AGENT_PROPOSED_BY = %w[ai_assistant automation_agent].freeze
  AI_SUGGESTION_KINDS = [ KnowledgeSuggestion::KIND_PROACTIVE ].freeze
  PROACTIVE_KNOWLEDGE_SUGGESTION_CHECK_INTERVAL = 10.minutes
  LAST_PAGE_VISIT_SESSION_LIMIT = 6

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :ensure_active_record_encryption_keys
  before_action :prune_workspace_session_state
  before_action :set_paper_trail_whodunnit
  before_action :ensure_realtime_channel_loaded
  around_action :use_user_time_zone
  after_action :warn_if_cookie_session_near_limit
  after_action :verify_pundit_authorization, unless: :devise_controller?
  after_action :store_last_workspace_slug!, if: :should_store_last_workspace_slug?

  rescue_from Pundit::NotAuthorizedError, with: :handle_not_authorized
  rescue_from ActionController::InvalidAuthenticityToken, with: :handle_invalid_authenticity_token
  rescue_from ActionDispatch::Cookies::CookieOverflow, with: :handle_cookie_overflow
  rescue_from ActiveRecord::Encryption::Errors::Configuration, with: :handle_encryption_configuration_error

  private

  def verify_pundit_authorization
    action_name == "index" ? verify_policy_scoped : verify_authorized
  end

  def should_store_last_workspace_slug?
    user_signed_in? &&
      request.get? &&
      params[:workspace_slug].present?
  end

  def handle_not_authorized
    redirect_back fallback_location: root_path, alert: "You are not authorized to perform this action."
  end

  def after_sign_in_path_for(resource_or_scope)
    stored_location = stored_location_for(resource_or_scope)
    return stored_location if stored_location.present?

    resource = resource_or_scope if resource_or_scope.is_a?(User)
    workspace = resource && preferred_workspace_for(resource)
    return workspace_path(workspace.slug) if workspace.present?

    super
  end

  def store_last_workspace_slug!
    return unless response.successful?
    return if session["notae_last_workspace_slug"].to_s == params[:workspace_slug].to_s

    session["notae_last_workspace_slug"] = params[:workspace_slug].to_s
  end

  def handle_invalid_authenticity_token(error = nil)
    log_session_diagnostic_event(reason: "invalid_authenticity_token", error: error)
    reset_session
    redirect_to new_user_session_path, alert: "Your session expired. Please sign in again."
  end

  def handle_cookie_overflow(error)
    log_session_diagnostic_event(reason: "cookie_overflow", error: error)
    reset_session
    redirect_to new_user_session_path, alert: "Your session data exceeded the browser limit. Please sign in again."
  end

  def handle_encryption_configuration_error(error)
    Rails.logger.error("[EncryptionConfig] #{error.class}: #{error.message}")

    respond_to do |format|
      format.json do
        render json: { error: { code: "encryption_unavailable", message: "Encryption configuration is unavailable." } },
               status: :service_unavailable
      end
      format.any do
        redirect_back fallback_location: root_path, alert: "Encryption configuration is unavailable. Please retry."
      end
    end
  end

  def settings_flash_stream(type, message)
    turbo_stream.replace(
      "settings_flash_messages",
      partial: "shared/flash_messages",
      locals: {
        flash_messages: [ [ type, message ] ],
        flash_dom_id: "settings_flash_messages",
        flash_host_class: "notae-settings-inline-flash-host"
      }
    )
  end

  def prune_workspace_session_state
    prune_legacy_workspace_session_state!
    Notae::SessionStatePruner.prune!(session)
    last_page_visit_store
  end

  def warn_if_cookie_session_near_limit
    return unless Notae::SessionDiagnostics.cookie_store?

    bytes = Notae::SessionDiagnostics.approximate_payload_bytes(session)
    return if bytes < Notae::SessionDiagnostics.warning_threshold_bytes

    log_session_diagnostic_event(reason: "cookie_session_near_limit", extra: { approximate_session_bytes: bytes })
  end

  def prune_legacy_workspace_session_state!
    session.delete(:notae_proactive_knowledge_suggestion_checks)
    session.delete(:notae_pending_knowledge_suggestion_generations)
  end

  def preferred_workspace_for(user)
    last_workspace_slug = session["notae_last_workspace_slug"].to_s.strip
    workspace_scope = user.workspaces.where.not(slug: [ nil, "" ])

    if last_workspace_slug.present?
      matched_workspace = workspace_scope.find_by(slug: last_workspace_slug)
      return matched_workspace if matched_workspace.present?
    end

    workspace_scope.order(:created_at).first
  end

  def set_ai_rail_usage_panel
    return unless user_signed_in?
    return if @ai_rail_workspace.blank?

    @ai_usage_panel = with_optional_schema_fallback(default: nil, feature: "AI usage panel") do
      build_ai_usage_panel(user: current_user, workspace: @ai_rail_workspace)
    end
  end

  def set_ai_rail_conversations
    return unless user_signed_in?

    @ai_rail_conversations = with_optional_schema_fallback(default: [], feature: "AI conversations") do
      recent_ai_conversations_for(user: current_user, window: 1.week, limit: ai_rail_conversation_limit).to_a.reverse
    end
  end

  def set_ai_agent_updates
    return unless user_signed_in?
    return if @ai_rail_workspace.blank?

    @ai_agent_updates = with_optional_schema_fallback(default: [], feature: "AI agent updates") do
      recent_ai_agent_updates_for(workspace: @ai_rail_workspace, limit: ai_agent_update_limit)
    end
  end

  def set_active_knowledge_suggestion
    return unless user_signed_in?
    return if @ai_rail_workspace.blank?
    return unless data_source_available?("knowledge_suggestions")

    @active_knowledge_suggestion = with_optional_schema_fallback(default: nil, feature: "knowledge suggestions") do
      current_active_suggestion_for(@ai_rail_workspace)
    end

    if @active_knowledge_suggestion.present?
      clear_knowledge_suggestion_generation_pending!(@ai_rail_workspace, kind: KnowledgeSuggestion::KIND_PROACTIVE)
      @pending_proactive_knowledge_suggestion = false
      return
    end

    @pending_proactive_knowledge_suggestion = knowledge_suggestion_generation_pending?(
      @ai_rail_workspace,
      kind: KnowledgeSuggestion::KIND_PROACTIVE
    )

    return unless should_generate_proactive_knowledge_suggestion?
    return if @pending_proactive_knowledge_suggestion
    return if proactive_knowledge_suggestion_recently_checked?(@ai_rail_workspace)
    return unless knowledge_suggestion_generation_context_available?(
      @ai_rail_workspace,
      kind: KnowledgeSuggestion::KIND_PROACTIVE
    )

    mark_proactive_knowledge_suggestion_checked!(@ai_rail_workspace)
    @pending_proactive_knowledge_suggestion =
      queue_knowledge_suggestion_generation!(@ai_rail_workspace, kind: KnowledgeSuggestion::KIND_PROACTIVE)
  end

  def recent_ai_conversations_for(user:, window: 1.week, limit: nil)
    return AiConversation.none unless data_source_available?("ai_conversations")

    workspace_ids = policy_scope(Workspace).select(:id)
    AiConversation
      .for_user(user)
      .where(workspace_id: workspace_ids)
      .where(created_at: window.ago..Time.current)
      .includes(:workspace)
      .recent_first
      .limit(limit || ai_rail_conversation_limit)
  end

  def ai_rail_conversation_limit
    AI_RAIL_CONVERSATION_LIMIT
  end

  def ai_agent_update_limit
    AI_AGENT_UPDATE_LIMIT
  end

  def external_app_base_url
    explicit_base_url = normalized_explicit_base_url(ENV["APP_BASE_URL"])
    return explicit_base_url if explicit_base_url.present?

    explicit_host = ENV["APP_HOST"].to_s.strip.presence
    if explicit_host.present?
      return base_url_from_host_config(
        host_value: explicit_host,
        port_value: ENV["APP_PORT"],
        protocol_value: ENV["APP_PROTOCOL"]
      )
    end

    mailer_url_options = Rails.application.config.action_mailer.default_url_options.to_h.symbolize_keys
    configured_host = mailer_url_options[:host].to_s.strip.presence
    if configured_host.present? && local_request_host? && !local_host?(configured_host)
      return base_url_from_host_config(
        host_value: configured_host,
        port_value: mailer_url_options[:port],
        protocol_value: mailer_url_options[:protocol]
      )
    end

    request.base_url
  end

  def recent_ai_agent_updates_for(workspace:, limit:, since: nil)
    updates = []

    if data_source_available?("workflow_runs")
      workflow_scope = policy_scope(WorkflowRun)
                       .for_workspace(workspace)
                       .where(trigger_source: AI_AGENT_TRIGGER_SOURCES)
      workflow_scope = workflow_scope.where("updated_at > ?", since) if since.present?
      updates.concat(
        workflow_scope
          .order(updated_at: :desc)
          .limit(limit)
          .map { |workflow_run| ai_agent_update_for_workflow_run(workflow_run) }
      )
    end

    if data_source_available?("agent_actions")
      action_scope = policy_scope(AgentAction)
                     .for_workspace(workspace)
                     .where(proposed_by: AI_AGENT_PROPOSED_BY)
      action_scope = action_scope.where("updated_at > ?", since) if since.present?
      updates.concat(
        action_scope
          .order(updated_at: :desc)
          .limit(limit)
          .map { |agent_action| ai_agent_update_for_agent_action(agent_action) }
      )
    end

    if data_source_available?("knowledge_suggestions")
      suggestion_scope = policy_scope(KnowledgeSuggestion)
                         .for_workspace(workspace)
                         .active
                         .where(kind: AI_SUGGESTION_KINDS)
      suggestion_scope = suggestion_scope.where("updated_at > ?", since) if since.present?
      updates.concat(
        suggestion_scope
          .recent_first
          .limit(limit)
          .map { |suggestion| ai_agent_update_for_knowledge_suggestion(suggestion) }
      )
    end

    updates.sort_by { |entry| -entry.fetch(:updated_at).to_i }.first(limit)
  end

  def normalized_explicit_base_url(value)
    raw_value = value.to_s.strip
    return if raw_value.blank?

    uri = URI.parse(raw_value)
    return if uri.host.blank?

    scheme = uri.scheme.to_s.presence || "https"
    base_url = +"#{scheme}://#{uri.host}"
    base_url << ":#{uri.port}" if include_port_in_base_url?(uri.port, scheme)
    base_url
  rescue URI::InvalidURIError
    nil
  end

  def base_url_from_host_config(host_value:, port_value:, protocol_value:)
    normalized_host = host_value.to_s.strip
    return if normalized_host.blank?

    explicit_base_url = normalized_explicit_base_url(normalized_host)
    return explicit_base_url if explicit_base_url.present?

    scheme = protocol_value.to_s.delete_suffix("://").presence || default_external_app_protocol(port_value)
    base_url = +"#{scheme}://#{normalized_host}"
    port_number = normalized_port_value(port_value)
    base_url << ":#{port_number}" if include_port_in_base_url?(port_number, scheme)
    base_url
  end

  def default_external_app_protocol(port_value)
    port_number = normalized_port_value(port_value)
    return "https" if port_number == 443
    return "http" if port_number == 80
    return "https" if request.ssl? || Rails.application.config.force_ssl || Rails.application.config.assume_ssl

    request.protocol.to_s.delete_suffix("://").presence || "http"
  end

  def normalized_port_value(value)
    value.to_i.positive? ? value.to_i : nil
  end

  def include_port_in_base_url?(port_value, scheme)
    port_number = normalized_port_value(port_value)
    return false if port_number.blank?
    return false if scheme.to_s == "https" && port_number == 443
    return false if scheme.to_s == "http" && port_number == 80

    true
  end

  def local_request_host?
    local_host?(request.host)
  end

  def local_host?(host_value)
    %w[localhost 127.0.0.1 ::1].include?(host_value.to_s.downcase)
  end

  def ai_agent_update_for_workflow_run(workflow_run)
    result_payload = workflow_run.result_json.to_h
    input_payload = workflow_run.input_json.to_h
    target_title = result_payload["title"].presence || input_payload["title"].presence || workflow_run.workflow_kind.humanize
    preview_lines = [
      "Workflow: #{workflow_run.workflow_kind.humanize}",
      "Status: #{workflow_run.status.humanize}",
      ("Record: #{target_title}" if target_title.present?),
      ("Error: #{workflow_run.error_message}" if workflow_run.error_message.present?),
      ("Source: #{workflow_run.trigger_source.to_s.humanize}" if workflow_run.trigger_source.present?)
    ].compact

    {
      id: "workflow_run:#{workflow_run.id}",
      title: target_title,
      preview: preview_lines.join("\n"),
      url: workflow_run_path(workspace_slug: workflow_run.workspace.slug, id: workflow_run.id),
      action_label: "Open full window",
      kind_label: "Workflow update",
      updated_at: workflow_run.updated_at,
      updated_at_iso8601: workflow_run.updated_at.iso8601
    }
  end

  def ai_agent_update_for_agent_action(agent_action)
    summary = helpers.agent_action_preview_summary(agent_action)
    preview_lines = [
      "Draft: #{agent_action.draft_type.to_s.humanize}",
      "Status: #{helpers.agent_action_status_badge(agent_action)}",
      ("Title: #{agent_action.title}" if agent_action.title.present?),
      ("Summary: #{summary}" if summary.present?),
      ("Target: #{agent_action.target_system.to_s.titleize}" if agent_action.target_system.present?)
    ].compact

    {
      id: "agent_action:#{agent_action.id}",
      title: agent_action.title,
      preview: preview_lines.join("\n"),
      url: agent_action_path(workspace_slug: agent_action.workspace.slug, id: agent_action.id),
      action_label: "Open full window",
      kind_label: "Draft update",
      updated_at: agent_action.updated_at,
      updated_at_iso8601: agent_action.updated_at.iso8601
    }
  end

  def ai_agent_update_for_knowledge_suggestion(suggestion)
    task_titles = Array(suggestion.task_suggestions_json).filter_map { |item| item["title"].to_s.strip.presence }.first(3)
    preview_lines = [
      "Suggestion: #{suggestion.kind == KnowledgeSuggestion::KIND_DAILY_SUMMARY ? 'Daily workspace brief' : 'Suggested next step'}",
      ("Summary: #{suggestion.summary}" if suggestion.summary.present?),
      *task_titles.map { |title| "Task: #{title}" }
    ].compact
    updated_at = suggestion.updated_at || suggestion.generated_at || suggestion.created_at || Time.current

    {
      id: "knowledge_suggestion:#{suggestion.id}",
      title: suggestion.title,
      preview: preview_lines.join("\n"),
      url: workspace_path(suggestion.workspace.slug, show_home: 1, anchor: "knowledge-suggestion-#{suggestion.id}"),
      action_label: "Open full window",
      kind_label: "Suggestion",
      updated_at: updated_at,
      updated_at_iso8601: updated_at.iso8601
    }
  end

  def current_active_suggestion_for(workspace)
    policy_scope(KnowledgeSuggestion)
      .for_workspace(workspace)
      .active
      .proactive
      .recent_first
      .first
  end

  def knowledge_task_databases_for(workspace)
    policy_scope(Database)
      .for_workspace(workspace)
      .active
      .select(:id, :name, :icon, :updated_at)
      .order(updated_at: :desc)
      .limit(24)
      .to_a
  end

  def should_generate_proactive_knowledge_suggestion?
    return false unless current_user.openai_api_key_configured?

    current_hour = Time.zone.now.hour
    return false unless current_hour >= 9 && current_hour < 18
    true
  end

  def proactive_knowledge_suggestion_recently_checked?(workspace)
    checked_at = proactive_knowledge_suggestion_checked_at(workspace)
    checked_at.present? && checked_at > PROACTIVE_KNOWLEDGE_SUGGESTION_CHECK_INTERVAL.ago
  end

  def proactive_knowledge_suggestion_checked_at(workspace)
    return nil if workspace.blank? || current_user.blank?

    value = Rails.cache.read(proactive_knowledge_suggestion_check_cache_key(workspace)).to_s.strip
    value = proactive_knowledge_suggestion_check_session_value_for(workspace) if value.blank?
    return nil if value.blank?

    Time.iso8601(value)
  rescue ArgumentError
    Rails.cache.delete(proactive_knowledge_suggestion_check_cache_key(workspace))
    clear_proactive_knowledge_suggestion_checked_in_session!(workspace)
    nil
  end

  def mark_proactive_knowledge_suggestion_checked!(workspace, at: Time.current)
    return if workspace.blank? || current_user.blank?

    Rails.cache.write(
      proactive_knowledge_suggestion_check_cache_key(workspace),
      at.iso8601,
      expires_in: PROACTIVE_KNOWLEDGE_SUGGESTION_CHECK_INTERVAL
    )
    record_proactive_knowledge_suggestion_checked_in_session!(workspace, at.iso8601)
  end

  def proactive_knowledge_suggestion_check_cache_key(workspace)
    "knowledge_suggestion_proactive_check:#{current_user.id}:#{workspace.id}"
  end

  def knowledge_suggestion_generation_pending?(workspace, kind:)
    cache_pending = Search::KnowledgeSuggestionGenerationTracker.pending?(user: current_user, workspace: workspace, kind: kind)
    session_pending = knowledge_suggestion_generation_pending_in_session?(workspace, kind: kind)

    if cache_pending
      mark_knowledge_suggestion_generation_pending_in_session!(workspace, kind: kind) unless session_pending
      return true
    end

    session_pending
  end

  def clear_knowledge_suggestion_generation_pending!(workspace, kind:)
    Search::KnowledgeSuggestionGenerationTracker.clear!(user: current_user, workspace: workspace, kind: kind)
    clear_knowledge_suggestion_generation_pending_in_session!(workspace, kind: kind)
  end

  def queue_knowledge_suggestion_generation!(workspace, kind:)
    Search::KnowledgeSuggestionGenerationTracker.mark_pending!(user: current_user, workspace: workspace, kind: kind)
    mark_knowledge_suggestion_generation_pending_in_session!(workspace, kind: kind)
    Search::GenerateKnowledgeSuggestionJob.perform_later(current_user.id, workspace.id, kind)
    true
  rescue StandardError => error
    Search::KnowledgeSuggestionGenerationTracker.clear!(user: current_user, workspace: workspace, kind: kind)
    clear_knowledge_suggestion_generation_pending_in_session!(workspace, kind: kind)
    log_knowledge_suggestion_enqueue_failure!(workspace: workspace, kind: kind, error: error)
    false
  end

  def log_knowledge_suggestion_enqueue_failure!(workspace:, kind:, error:)
    Rails.logger.error(
      "[KnowledgeSuggestionQueue] Failed to enqueue #{kind} for workspace=#{workspace&.id} user=#{current_user&.id}: #{error.class}: #{error.message}"
    )

    return unless current_user.present? && workspace.present?
    return unless data_source_available?("ai_usage_logs")

    with_optional_schema_fallback(default: nil, feature: "knowledge suggestion enqueue logging") do
      Search::AiUsageLogger.log_outcome!(
        user: current_user,
        workspace: workspace,
        operation: AiUsageLog::OP_KNOWLEDGE_SUGGESTION_FAILURE,
        model: "background_job",
        metadata: {
          kind: kind,
          stage: "enqueue",
          error_class: error.class.name,
          error_message: error.message.to_s.first(300)
        }
      )
    end
  end

  def knowledge_suggestion_generation_context_available?(workspace, kind:)
    return false if workspace.blank? || current_user.blank?

    @knowledge_suggestion_generation_context_available ||= {}
    cache_key = "#{workspace.id}:#{kind}"
    return @knowledge_suggestion_generation_context_available[cache_key] if @knowledge_suggestion_generation_context_available.key?(cache_key)

    @knowledge_suggestion_generation_context_available[cache_key] =
      Search::PersistKnowledgeSuggestionService.generation_context_available?(
        user: current_user,
        workspace: workspace,
        kind: kind
      )
  end

  def last_page_visit_store
    raw_store = session["notae_last_page_visits"]
    pruned_store =
      Notae::SessionStatePruner
        .normalized_workspace_scoped_hash(raw_store, limit: LAST_PAGE_VISIT_SESSION_LIMIT)
        .transform_values { |value| value.to_s }

    session["notae_last_page_visits"] = pruned_store if raw_store != pruned_store
    pruned_store
  end

  def remember_last_page_visit_for!(workspace:, page:)
    return if workspace.blank? || page.blank?

    store = last_page_visit_store.dup
    workspace_key = workspace.id.to_s
    store.delete(workspace_key)
    store[workspace_key] = page.id.to_s
    session["notae_last_page_visits"] = store.to_a.last(LAST_PAGE_VISIT_SESSION_LIMIT).to_h
  end

  def proactive_knowledge_suggestion_check_session_value_for(workspace)
    record = session[:notae_recent_proactive_knowledge_check]
    return "" unless record.is_a?(Hash)
    return "" unless record["workspace_id"].to_s == workspace.id.to_s

    record["checked_at"].to_s
  end

  def record_proactive_knowledge_suggestion_checked_in_session!(workspace, value)
    session[:notae_recent_proactive_knowledge_check] = {
      "workspace_id" => workspace.id.to_s,
      "checked_at" => value.to_s
    }
  end

  def clear_proactive_knowledge_suggestion_checked_in_session!(workspace)
    record = session[:notae_recent_proactive_knowledge_check]
    return unless record.is_a?(Hash)
    return unless workspace.blank? || record["workspace_id"].to_s == workspace.id.to_s

    session.delete(:notae_recent_proactive_knowledge_check)
  end

  def knowledge_suggestion_generation_pending_in_session?(workspace, kind:)
    store = knowledge_suggestion_generation_pending_store
    record = store[kind.to_s]
    return false unless record.is_a?(Hash)
    return false unless record["workspace_id"].to_s == workspace.id.to_s
    if kind.to_s == KnowledgeSuggestion::KIND_DAILY_SUMMARY
      current_local_date = Time.use_zone(current_user.time_zone.presence || Time.zone) { Date.current.iso8601 }
      return false unless record["local_date"].to_s == current_local_date
    end

    recorded_at = Time.zone.parse(record["recorded_at"].to_s)
    return true if recorded_at.present? && recorded_at >= knowledge_suggestion_generation_pending_ttl_for(kind).ago

    store.delete(kind.to_s)
    session[:notae_recent_pending_knowledge_generation] = store
    false
  rescue ArgumentError
    store.delete(kind.to_s)
    session[:notae_recent_pending_knowledge_generation] = store
    false
  end

  def mark_knowledge_suggestion_generation_pending_in_session!(workspace, kind:)
    store = knowledge_suggestion_generation_pending_store
    store[kind.to_s] = {
      "workspace_id" => workspace.id.to_s,
      "recorded_at" => Time.current.iso8601
    }
    if kind.to_s == KnowledgeSuggestion::KIND_DAILY_SUMMARY
      store[kind.to_s]["local_date"] = Time.use_zone(current_user.time_zone.presence || Time.zone) { Date.current.iso8601 }
    end
    session[:notae_recent_pending_knowledge_generation] = store
  end

  def clear_knowledge_suggestion_generation_pending_in_session!(workspace, kind:)
    store = knowledge_suggestion_generation_pending_store
    record = store[kind.to_s]
    return unless record.is_a?(Hash)
    return unless record["workspace_id"].to_s == workspace.id.to_s

    store.delete(kind.to_s)
    session[:notae_recent_pending_knowledge_generation] = store
  end

  def knowledge_suggestion_generation_pending_store
    raw_store = session[:notae_recent_pending_knowledge_generation]
    return {} unless raw_store.is_a?(Hash)

    raw_store.stringify_keys.transform_values do |record|
      record.is_a?(Hash) ? record.stringify_keys.slice("workspace_id", "recorded_at", "local_date") : {}
    end
  end

  def knowledge_suggestion_generation_pending_ttl_for(kind)
    kind.to_s == KnowledgeSuggestion::KIND_DAILY_SUMMARY ? 45.minutes : 15.minutes
  end

  def build_ai_usage_panel(user:, workspace:)
    return nil unless data_source_available?("ai_usage_logs")

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

  def ensure_active_record_encryption_keys
    Notae::ActiveRecordEncryptionBootstrap.configure!
  end

  def log_session_diagnostic_event(reason:, error: nil, extra: {})
    payload = Notae::SessionDiagnostics.event_payload(
      request: request,
      session: session,
      current_user: current_user,
      reason: reason,
      error: error
    ).merge(extra)

    Notae::SessionDiagnostics.instrument!(payload)
    Notae::SessionEventStore.record!(
      user_id: current_user&.id,
      event: payload.merge(recorded_at: Time.current.iso8601)
    )
    Rails.logger.warn("[SessionDiagnostic] #{payload.to_json}")
  rescue StandardError => diagnostic_error
    Rails.logger.warn("[SessionDiagnostic] failed to capture #{reason}: #{diagnostic_error.class}: #{diagnostic_error.message}")
  end

  def use_user_time_zone(&block)
    return yield unless user_signed_in?

    zone_name = current_user.time_zone.presence
    zone = zone_name && ActiveSupport::TimeZone[zone_name]
    return yield unless zone

    Time.use_zone(zone, &block)
  end

  def with_optional_schema_fallback(default:, feature:)
    yield
  rescue ActiveRecord::StatementInvalid => e
    raise unless optional_schema_error?(e)

    Rails.logger.warn("[OptionalSchema] Skipping #{feature}: #{e.class}: #{e.message}")
    default
  end

  def data_source_available?(name)
    ActiveRecord::Base.connection.data_source_exists?(name)
  rescue ActiveRecord::StatementInvalid => e
    raise unless optional_schema_error?(e)

    false
  end

  def optional_schema_error?(error)
    return true if optional_schema_error_message?(error.message)

    cause = error.cause
    return false if cause.blank?

    optional_schema_error_message?(cause.message)
  end

  def optional_schema_error_message?(message)
    text = message.to_s
    text.include?("PG::UndefinedTable") ||
      text.include?("PG::UndefinedColumn") ||
      text.include?("no such table") ||
      text.include?("no such column") ||
      (text.include?("relation") && text.include?("does not exist"))
  end
end
