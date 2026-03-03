class ApplicationController < ActionController::Base
  include Pundit::Authorization

  AI_RAIL_CONVERSATION_LIMIT = 20

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :ensure_active_record_encryption_keys
  before_action :set_paper_trail_whodunnit
  before_action :set_unread_notifications_count
  before_action :set_ai_rail_context, if: :load_shell_context?
  before_action :set_ai_rail_conversations, if: :load_shell_context?
  before_action :set_ai_rail_usage_panel, if: :load_shell_context?
  before_action :ensure_realtime_channel_loaded
  around_action :use_user_time_zone
  after_action :verify_pundit_authorization, unless: :devise_controller?

  rescue_from Pundit::NotAuthorizedError, with: :handle_not_authorized
  rescue_from ActionController::InvalidAuthenticityToken, with: :handle_invalid_authenticity_token
  rescue_from ActiveRecord::Encryption::Errors::Configuration, with: :handle_encryption_configuration_error

  private

  def verify_pundit_authorization
    action_name == "index" ? verify_policy_scoped : verify_authorized
  end

  def load_shell_context?
    request.get? && request.format.html?
  end

  def handle_not_authorized
    redirect_back fallback_location: root_path, alert: "You are not authorized to perform this action."
  end

  def handle_invalid_authenticity_token
    reset_session
    redirect_to new_user_session_path, alert: "Your session expired. Please sign in again."
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

  def set_unread_notifications_count
    unless load_shell_context?
      @unread_notifications_count = 0
      return
    end

    @unread_notifications_count =
      if user_signed_in?
        with_optional_schema_fallback(default: 0, feature: "unread notifications") do
          policy_scope(Notification).unread.count
        end
      else
        0
      end
  end

  def set_ai_rail_context
    return unless user_signed_in?

    @ai_rail_workspace = with_optional_schema_fallback(default: nil, feature: "AI rail workspace context") do
      if params[:workspace_slug].present?
        policy_scope(Workspace).find_by(slug: params[:workspace_slug])
      end
    end
    @ai_rail_workspace = with_optional_schema_fallback(default: @ai_rail_workspace, feature: "AI rail workspace fallback") do
      @ai_rail_workspace || policy_scope(Workspace).order(updated_at: :desc).first
    end
    @ai_rail_current_page_id = params[:controller] == "pages" && params[:action] == "show" ? params[:id] : nil
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
    primary_key = ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"].presence ||
                  credentials_active_record_encryption_value(:primary_key)
    deterministic_key = ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"].presence ||
                        credentials_active_record_encryption_value(:deterministic_key)
    key_derivation_salt = ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"].presence ||
                          credentials_active_record_encryption_value(:key_derivation_salt)

    if primary_key.blank? || deterministic_key.blank? || key_derivation_salt.blank?
      secret = encryption_bootstrap_secret
      return if secret.blank?

      primary_key ||= derive_encryption_key(secret, "primary")
      deterministic_key ||= derive_encryption_key(secret, "deterministic")
      key_derivation_salt ||= derive_encryption_key(secret, "salt")
    end

    [ Rails.application.config.active_record.encryption, ActiveRecord::Encryption.config ].each do |encryption_config|
      next if encryption_config.has_primary_key? && encryption_config.has_deterministic_key? && encryption_config.has_key_derivation_salt?

      encryption_config.primary_key = primary_key unless encryption_config.has_primary_key?
      encryption_config.deterministic_key = deterministic_key unless encryption_config.has_deterministic_key?
      encryption_config.key_derivation_salt = key_derivation_salt unless encryption_config.has_key_derivation_salt?
      encryption_config.support_unencrypted_data = true
      encryption_config.extend_queries = true
    end
  end

  def encryption_bootstrap_secret
    configured_secret = ENV["ACTIVE_RECORD_ENCRYPTION_BOOTSTRAP_SECRET"].to_s.presence ||
                        ENV["SECRET_KEY_BASE"].to_s.presence ||
                        safe_credentials_secret_key_base
    return configured_secret if configured_secret.present?
    return "notae-active-record-encryption-fallback-#{Rails.env}" unless Rails.env.production?

    nil
  end

  def safe_credentials_secret_key_base
    Rails.application.credentials.secret_key_base.to_s.presence
  rescue ActiveSupport::MessageEncryptor::InvalidMessage,
         ActiveSupport::EncryptedFile::MissingKeyError,
         ArgumentError
    nil
  end

  def credentials_active_record_encryption_value(key_name)
    config_hash = Rails.application.credentials[:active_record_encryption]
    return nil unless config_hash.respond_to?(:[])

    value = config_hash[key_name] || config_hash[key_name.to_s]
    value.to_s.strip.presence
  rescue ActiveSupport::MessageEncryptor::InvalidMessage,
         ActiveSupport::EncryptedFile::MissingKeyError,
         ArgumentError
    nil
  end

  def derive_encryption_key(secret, context)
    OpenSSL::HMAC.hexdigest("SHA256", secret, "notae:active-record-encryption:#{context}")
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
